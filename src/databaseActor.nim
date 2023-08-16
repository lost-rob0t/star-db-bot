import mycouch
import zmq
import starRouter
import json, jsony
import asyncdispatch
import cligen
import os

proc getRev(db: AsyncCouchDBClient, database, id: string): Future[string] {.async.} =
  let rev = await db.getDoc(database, id)
  # TODO get mycouch to use the E-tag header
  result = rev["_rev"].getStr("")

proc insertDocument*(db: AsyncCouchDBClient, document: JsonNode) {.async.} =
  if not document.hasKey("dataset"):
    return

  let database = document{"dataset"}.getStr("")
  let id = document{"_id"}.getStr("")
  try:
    discard await db.createDoc(database, document)
  except CouchDBError:
    # Should i be doing this?
    let rev = await db.getRev(database, id)
    let id = document{"_id"}.getStr("")
    discard await db.createOrUpdateDoc(database, id, rev,  document)



proc mainLoop(client: Client, db: AsyncCouchDBClient) {.async.} =
  var db = db
  var client = client
  client.connect()
  proc insertMessage[T](doc: proto.Message[T]) {.async.} =
    # FIXME This is stupid and slow
    var document = doc.data
    document{"_id"} = %document["id"].getStr("")
    document.delete("_id")
    await db.insertDocument(doc.data)
  proc filterMessages[T](doc: proto.Message[T]): bool =
    let etype = $doc.typ
    case etype:
      of EventType.newDocument.ord:
        return true
      of EventType.updateDocument.ord:
        return true
      of EventType.deleteDocument.ord:
        return false
      else:
        return false

  var inbox = proto.Message[JsonNode].newInbox(100)
  inbox.registerCB(insertMessage)
  inbox.registerFilter(filterMessages)
  await Message[JsonNode].runInbox(client, inbox)

proc main(apiAddress: string = "tcp://127.0.0.1:6001", publisherAddress: string = "tcp://127.0.0.1:6000") =
  var client = newClient("couchdb", publisherAddress, apiAddress, 10, @["Username"])
  var db = newAsyncCouchDBClient()
  discard waitFor db.cookieAuth(getEnv("DB_USER"), getEnv("DB_PASS"))
  echo "end of setup"
  waitFor mainLoop(client, db)


dispatch(main)

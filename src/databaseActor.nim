import starRouter
import mycouch
import morelogging
import zmq
import json
import asyncdispatch
import strutils
import os
import times
import logging
import cligen
import strformat
type
  DatabaseActor = ref object
    dbUser: string
    dbPass: string
    db*: AsyncCouchDBClient
    dbName*: string
    log*: AsyncFileLogger



proc logError(actor: DatabaseActor, exception: ref Exception) =
    actor.log.error(getCurrentExceptionMsg())


proc login(actor: DatabaseActor) {.async.} =
  try:
    # Needed since for some reason couch might not respect my cookie timeout :(
    actor.log.debug "Logging in....."
    let logInfo = await actor.db.cookieAuth(actor.dbUser, actor.dbPass)
    actor.log.info(logInfo)
    actor.log.debug "Logged in!"
  except CouchDBError as e:
    actor.logError(e)

proc filterTrue(doc: Message[string]): bool =
  result = true

proc upsert(actor: DatabaseActor, doc: JsonNode) {.async.} =
  try:
    let id = doc["_id"].getStr()
    actor.log.info(fmt"upserting: {id}")
    let oldDoc = await actor.db.getDoc(actor.dbName, id)
    var newDoc = doc
    let rev = oldDoc["_rev"].getStr()
    newDoc["rev"] = newJString(rev)
    let upsert = await actor.db.createOrUpdateDoc(actor.dbName, id, rev, newDoc)
    actor.log.info($upsert)
  except Exception as e:
    actor.logError(e)

proc mainLoop*(router: Client, actor: DatabaseActor) =
  var
    actor = actor
    inbox = string.newInbox(500)
    t = now().toTime().toUnix()
  proc handleMessage(doc: Message[string]) {.async.} =
    var document = doc.data.parseJson()
    let id = document["id"]
    document["_id"] = %id
    document.delete("id")
    try:
      let insertInfo = await actor.db.createDoc(actor.dbName, document)
      actor.log.info($insertInfo)
    except Exception as e:
      actor.logError(e)
      await actor.upsert(document)
  inbox.registerFilter(filterTrue)
  inbox.registerCB(handleMessage)
  waitFor runStringInbox(router, inbox)
  # For some reason couchdb noes not respect the expire time on a cookie,
  # this is to auto login, to keep it valid.
  # let now = now().toTime().toUnix
  # if now - t >= 180:
  #   await actor.login

proc main(dbName: string = getEnv("DB_NAME", "star-intel"),
          dbUser: string = getEnv("DB_USER", "admin"),
          dbPass: string = getEnv("DB_PASS", "password"),
          dbHost: string = getEnv("DB_HOST", "http://127.0.0.1"),
          dbPort: int = getEnv("DB_PORT", "5984").parseInt(),
          level:  string = getEnv("COUCHDB_LOG_LEVEL", "lvlInfo"),
          apiAddress: string = getEnv("ROUTER_API_ADDRESS", "tcp://127.0.0.1:6001"),
          subAddress: string = getEnv("ROUTER_PUB_ADDRESS", "tcp://127.0.0.1:6000")
         ) =
  var actor = DatabaseActor(dbUser: dbUser, dbPass: dbPass, dbName: dbName)
  actor.db = newAsyncCouchDBClient(dbHost, dbPort)
  let level = parseEnum[Level](level)
  actor.log = newAsyncFileLogger(filename_tpl=getEnv("COUCHDB_LOG", "$appname.$y$MM$dd.log"), flush_threshold=level)
  waitFor actor.login()
  var client = newClient("couchdb", subAddress, apiAddress, 10_000, @[""])
  waitFor client.connect()
  client.mainLoop(actor)
when isMainModule:
  dispatch main

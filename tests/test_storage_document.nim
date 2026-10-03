import std/json
import ../src/storage_document
let doc = %*{"id":"document:one", "dataset":"test", "dtype":"document", "schemaVersion":"0.10.1", "deleted":false, "extensions":{"opaque":nil}}
let stored = storageDocument(doc)
doAssert stored["_id"] == doc["id"]
doAssert stored["id"] == doc["id"]
doAssert not doc.hasKey("_id")
doAssert stored["deleted"].getBool == false
var rev = parseJson($doc)
rev["rev"] = %"1-test"
doAssert storageDocument(rev)["_rev"].getStr == "1-test"
for key in ["schemaVersion", "id"]:
  var invalid = parseJson($doc)
  invalid.delete(key)
  var rejected = false
  try: discard storageDocument(invalid)
  except ValueError: rejected = true
  doAssert rejected
var invalid = parseJson($doc)
invalid["_id"] = %"storage-leak"
var rejected = false
try: discard storageDocument(invalid)
except ValueError: rejected = true
doAssert rejected
echo "canonical storage checks passed"

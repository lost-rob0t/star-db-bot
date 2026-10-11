## Validate the wire document before adding CouchDB-only storage metadata.
import std/json
import starintel_doc/canonical

proc storageDocument*(document: JsonNode): JsonNode =
  let validation = validateDocument(document)
  if not validation.ok:
    raise newException(ValueError, validation.category & ": " & validation.message)
  result = parseJson($document)
  result["_id"] = result["id"]
  if result.hasKey("rev"):
    result["_rev"] = result["rev"]
    result.delete("rev")

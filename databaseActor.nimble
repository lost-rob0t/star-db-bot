# Package

version       = "0.1.0"
author        = "nsaspy"
description   = "The database actor for starRouter"
license       = "MIT"
srcDir        = "src"
bin           = @["databaseActor"]


# Dependencies

requires "nim >= 1.6.14"
requires "mycouch"
requires "zmq"
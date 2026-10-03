# Package

version       = "0.1.0"
author        = "nsaspy"
description   = "The database actor for starRouter"
license       = "MIT"
srcDir        = "src"
bin           = @["databaseActor"]


# Dependencies

requires "nim >= 2.0.0"
requires "mycouch"
requires "zmq"
requires "cligen"
requires "morelogging"
requires "https://github.com/lost-rob0t/starRouter.git"

requires "https://github.com/lost-rob0t/starintel-doc.nim.git#827f2c072e9893561a1925c47f898458bafd6759"

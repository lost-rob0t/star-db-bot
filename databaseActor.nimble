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
requires "https://github.com/lost-rob0t/starRouter.git#20e5c9e8bf49660fd230d8e7306dd9209648f6e9"

requires "https://github.com/lost-rob0t/starintel-doc.nim.git#827f2c072e9893561a1925c47f898458bafd6759"

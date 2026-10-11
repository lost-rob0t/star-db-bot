{
  description = "Locked StarIntel CouchDB actor producer";
  inputs = {
    star-router.url = "github:lost-rob0t/starRouter/20e5c9e8bf49660fd230d8e7306dd9209648f6e9";
    nixpkgs.follows = "star-router/nixpkgs";
    starintel-doc.follows = "star-router/starintel-doc";
    mycouch = { url = "github:hamidb80/mycouch/abf4365452e21cc3239ebed617a949aeca05d39c"; flake = false; };
    macroutils = { url = "github:PMunch/macroutils/e6357d428f3888c3b0c068a9e2bd0cf66d25e3cd"; flake = false; };
    macroplus = { url = "github:hamidb80/macroplus/ab49b1b2bfd92fbf69b39ddb3096472d72aaf815"; flake = false; };
    morelogging = { url = "github:FedericoCeratto/nim-morelogging/ea61e0e8f49db122cb12c263ba05313a29aeea81"; flake = false; };
    zip = { url = "github:nim-lang/zip/1bc02a1d888cedb53075ca81d9fe3553c16ef10a"; flake = false; };
  };
  outputs = { self, nixpkgs, star-router, starintel-doc, mycouch, macroutils, macroplus, morelogging, zip }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      python = pkgs.python3.withPackages (p: [ p.pyzmq ]);
      paths = "--noNimblePath --path:src --path:${starintel-doc}/src --path:${star-router}/src --path:${mycouch}/src --path:${macroutils}/src --path:${macroplus}/src --path:${morelogging} --path:${zip} --path:${star-router.inputs.cligen} --path:${star-router.inputs.zmq} --path:$TMPDIR/ulid-deps";
      libraries = pkgs.lib.makeLibraryPath [ pkgs.zeromq pkgs.pcre pkgs.openssl pkgs.zlib ];
      actor = pkgs.stdenv.mkDerivation {
        pname = "databaseActor";
        version = "0.1.0";
        src = self;
        nativeBuildInputs = [ pkgs.nim pkgs.makeWrapper python ];
        buildInputs = [ pkgs.openssl ];
        buildPhase = ''
          # Same pinned ULID/Nim 2 module-name collision as the sibling actors.
          mkdir -p "$TMPDIR/ulid-deps"
          cp -r ${star-router.inputs.ulid}/src/. "$TMPDIR/ulid-deps/"
          cp -r ${star-router.inputs.random}/src/. "$TMPDIR/ulid-deps/"
          mv "$TMPDIR/ulid-deps/random.nim" "$TMPDIR/ulid-deps/ulid_random.nim"
          chmod u+w "$TMPDIR/ulid-deps/ulid.nim"
          substituteInPlace "$TMPDIR/ulid-deps/ulid.nim" --replace-fail 'import pkg/random' 'import ulid_random'
          nim c -d:release -d:ssl ${paths} --nimcache:"$TMPDIR/nimcache" --out:databaseActor src/databaseActor.nim
        '';
        doCheck = true;
        checkPhase = ''
          export LD_LIBRARY_PATH=${libraries}
          nim c -r ${paths} --nimcache:"$TMPDIR/test-cache" --out:test-storage tests/test_storage_document.nim
        '';
        installPhase = ''
          mkdir -p "$out/bin"
          install -m755 databaseActor "$out/bin/databaseActor"
          wrapProgram "$out/bin/databaseActor" --prefix LD_LIBRARY_PATH : ${libraries} \
            --set-default SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
        '';
        doInstallCheck = true;
        installCheckPhase = ''
          unset LD_LIBRARY_PATH
          python3 tests/installed_actor.py "$out/bin/databaseActor" \
            ${star-router.packages.${system}.default}/bin/starRouter ${pkgs.couchdb3}
        '';
        meta = { mainProgram = "databaseActor"; platforms = [ system ]; };
      };
    in {
      packages.${system} = { default = actor; databaseActor = actor; };
      apps.${system} = {
        default = self.apps.${system}.databaseActor;
        databaseActor = { type = "app"; program = "${actor}/bin/databaseActor"; };
      };
      checks.${system}.default = actor;
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.nim python ];
        LD_LIBRARY_PATH = libraries;
      };
    };
}

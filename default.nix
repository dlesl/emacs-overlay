self: super:
let

  mkExDrv = emacsPackages: name: args: let
    repoMeta = super.lib.importJSON (./repos/exwm/. + "/${name}.json");
  in emacsPackages.melpaBuild (args // {
    pname   = name;
    ename   = name;
    version = repoMeta.version;
    recipe  = builtins.toFile "recipe" ''
      (${name} :fetcher github
      :repo "ch11ng/${name}")
    '';

    src = super.fetchFromGitHub {
      owner  = "ch11ng";
      repo   = name;
      inherit (repoMeta) rev sha256;
    };
  });

  mkGitEmacs = namePrefix: jsonFile: attrsFn:
    (self.emacs.override { srcRepo = true; }).overrideAttrs(old: (let
      repoMeta = super.lib.importJSON jsonFile;
      attrs = {
        name = "${namePrefix}-${repoMeta.version}";
        inherit (repoMeta) version;
        src = super.fetchFromGitHub {
          owner = "emacs-mirror";
          repo = "emacs";
          inherit (repoMeta) sha256 rev;
        };
        buildInputs = old.buildInputs ++ [ super.jansson super.harfbuzz.dev ];
        patches = [
          ./patches/tramp-detect-wrapped-gvfsd.patch
          ./patches/clean-env.patch
        ];
        postPatch = ''
          substituteInPlace lisp/loadup.el \
          --replace '(emacs-repository-get-version)' '"${repoMeta.rev}"' \
          --replace '(emacs-repository-get-branch)' '"master"'
        '';
      };
    in attrs // attrsFn (old // attrs)));

  emacsGit = mkGitEmacs "emacs-git" ./repos/emacs/emacs-master.json (_: { });

  emacsGcc = mkGitEmacs "emacs-gcc" ./repos/emacs/emacs-feature_native-comp.json (old: {
    # When this is enabled, emacs does native compilation lazily after starting
    # up, resulting in quicker package builds up-front, at the cost of slower
    # running emacs until everything has been compiled. Since the elpa files in
    # the nix store are read-only and we have binary caches, we prefer the
    # longer AOT compilation instead of this flag.
    # makeFlags = [ "NATIVE_FAST_BOOT=1" ];

    LIBRARY_PATH = "${super.lib.getLib self.stdenv.cc.libc}/lib";

    configureFlags = old.configureFlags ++ [ "--with-nativecomp" ];

    buildInputs = old.buildInputs ++ [ self.libgccjit ];
  });

  emacsUnstable = let
    repoMeta = super.lib.importJSON ./repos/emacs/emacs-unstable.json;
  in (self.emacs.override { srcRepo = true; }).overrideAttrs(old: {
    name = repoMeta.version;
    inherit (repoMeta) version;
    src = super.fetchFromGitHub {
      owner = "emacs-mirror";
      repo = "emacs";
      inherit (repoMeta) sha256 rev;
    };
    buildInputs = old.buildInputs ++ [ super.jansson super.harfbuzz.dev ];
    patches = [
      ./patches/tramp-detect-wrapped-gvfsd-27.patch
      ./patches/clean-env.patch
    ];
  });

  emacsMacportUnstable = let
    repoMeta = super.lib.importJSON ./repos/emacs/emacs-macport-unstable.json;
  in self.emacsMacport.overrideAttrs(old: {
    name = repoMeta.version;
    inherit (repoMeta) version;
    src = super.fetchgit {
      url = "https://bitbucket.org/mituharu/emacs-mac.git";
      inherit (repoMeta) sha256 rev;
    };
    buildInputs = old.buildInputs ++ [ super.jansson ];
    patches = [
      ./patches/clean-env.patch
    ];
    postUnpack = ''
      # extract retina image resources
      tar xzfv $hiresSrc --strip 1 -C $sourceRoot
    '';
    postPatch = ''
      substituteInPlace lisp/international/mule-cmds.el \
        --replace /usr/share/locale ${super.gettext}/share/locale
      # use newer emacs icon
      cp nextstep/Cocoa/Emacs.base/Contents/Resources/Emacs.icns mac/Emacs.app/Contents/Resources/Emacs.icns
      # Fix sandbox impurities.
      substituteInPlace Makefile.in --replace '/bin/pwd' 'pwd'
      substituteInPlace lib-src/Makefile.in --replace '/bin/pwd' 'pwd'
    '';
    preConfigure = "./autogen.sh";
  });

in {
  inherit emacsGit emacsUnstable emacsMacportUnstable;

  inherit emacsGcc;

  emacsGit-nox = ((emacsGit.override {
    withX = false;
    withGTK2 = false;
    withGTK3 = false;
  }).overrideAttrs(oa: {
    name = "${oa.name}-nox";
  }));

  emacsUnstable-nox = ((emacsUnstable.override {
    withX = false;
    withGTK2 = false;
    withGTK3 = false;
  }).overrideAttrs(oa: {
    name = "${oa.name}-nox";
  }));

  emacsWithPackagesFromUsePackage = import ./elisp.nix { pkgs = self; };

  emacsWithPackagesFromPackageRequires = import ./packreq.nix { pkgs = self; };

  emacsPackagesFor = emacs: (
    (super.emacsPackagesFor emacs).overrideScope'(eself: esuper: let

      melpaStablePackages = esuper.melpaStablePackages.override {
        archiveJson = ./repos/melpa/recipes-archive-melpa.json;
      };

      melpaPackages = esuper.melpaPackages.override {
        archiveJson = ./repos/melpa/recipes-archive-melpa.json;
      };

      elpaPackages = esuper.elpaPackages.override {
        generated = ./repos/elpa/elpa-generated.nix;
      };

      orgPackages = esuper.orgPackages.override {
        generated = ./repos/org/org-generated.nix;
      };

      epkgs = esuper.override {
        inherit melpaStablePackages melpaPackages elpaPackages orgPackages;
      };

    in epkgs // {
      xelb = mkExDrv eself "xelb" {
        packageRequires = [ eself.cl-generic eself.emacs ];
      };

      exwm = mkExDrv eself "exwm" {
        packageRequires = [ eself.xelb ];
      };
    }));

}

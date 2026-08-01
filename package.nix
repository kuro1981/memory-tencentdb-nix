{ lib
, buildNpmPackage
, nodejs
}:

let
  version = "1.0.1";

  # `nix build` が失敗したときに表示される正しい値へ差し替える。
  # scripts/update.sh が自動で更新する。
  npmDepsHash = "sha256-fVGiAEuvEhayla9p9VIrK08ZHLBIdmTSHk4FhcHDTc0=";
in
buildNpmPackage {
  pname = "memory-tencentdb";
  inherit version npmDepsHash;

  src = ./.;

  # ラッパーは依存を引くだけでビルド対象を持たない
  dontNpmBuild = true;

  inherit nodejs;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules $out/bin
    cp -r node_modules/. $out/lib/node_modules/

    # 本体が公開する実行ファイルを $out/bin へ露出させる
    pkgDir="$out/lib/node_modules/@tencentdb-agent-memory/memory-tencentdb"
    if [ -d "$pkgDir/bin" ]; then
      for f in "$pkgDir"/bin/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        name="''${name%.mjs}"
        name="''${name%.js}"
        chmod +x "$f"
        ln -s "$f" "$out/bin/$name"
      done
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "TencentDB Agent Memory plugin — local long-term memory (L0→L1→…) for OpenClaw / Hermes";
    homepage = "https://github.com/TencentCloud/TencentDB-Agent-Memory";
    license = licenses.asl20;
    platforms = platforms.linux ++ platforms.darwin;
  };
}

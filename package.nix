{ lib
, runtimeShell
, buildNpmPackage
, nodejs
}:

let
  version = "1.0.3";

  # `nix build` が失敗したときに表示される正しい値へ差し替える。
  # scripts/update.sh が自動で更新する。
  npmDepsHash = "sha256-JI1VAbD4XE00gXNyHX1X6AkeVtYc8sQRL+Ywdr+rpq8=";
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

    pkgDir="$out/lib/node_modules/@tencentdb-agent-memory/memory-tencentdb"

    # 本体が公開する実行ファイルを $out/bin へ露出させる
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

    # ゲートウェイの起動ラッパー。
    # 上流は dist にゲートウェイを含めず src/gateway/server.ts を直接実行する
    # 設計なので、tsx（本番依存として同梱される）で起動する。
    # 手で `cd <dir> && pnpm exec tsx src/gateway/server.ts` と書く必要をなくし、
    # パスをストアに固定するためのもの。
    if [ -f "$pkgDir/src/gateway/server.ts" ]; then
      cat > $out/bin/memory-tencentdb-gateway <<EOF
#!${runtimeShell}
exec ${nodejs}/bin/node \\
  "$out/lib/node_modules/tsx/dist/cli.mjs" \\
  "$pkgDir/src/gateway/server.ts" "\$@"
EOF
      chmod +x $out/bin/memory-tencentdb-gateway
    else
      echo "ERROR: src/gateway/server.ts not found — upstream layout changed" >&2
      exit 1
    fi

    # Hermes 側の Python プラグイン本体の所在を露出させる。
    # ~/.hermes/plugins/memory_tencentdb へ配置する際の参照元になる。
    if [ -d "$pkgDir/hermes-plugin" ]; then
      ln -s "$pkgDir/hermes-plugin" "$out/hermes-plugin"
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

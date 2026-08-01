# memory-tencentdb-nix

Nix packaging for [`@tencentdb-agent-memory/memory-tencentdb`](https://www.npmjs.com/package/@tencentdb-agent-memory/memory-tencentdb) — the TencentDB Agent Memory plugin providing local long-term memory (L0→L1→…) for OpenClaw / Hermes.

外部ホスト型の記憶サービスに依存せず、ローカルで長期記憶を持たせるためのプラグインです。

---

## なぜこのリポジトリがあるか

上流は npm パッケージとして公開されているが、`buildNpmPackage` は `package-lock.json` を必要とする。npm 公開時の tarball にはロックファイルが含まれないため、**依存を引くだけの最小ラッパー**（`package.json` + `package-lock.json`）を用意して nix でビルドできるようにしている。

これにより、

- バージョンが nix で固定され、`flake.lock` で再現性が担保される
- `node_modules` が nix ストアに入り、ホームディレクトリを汚さない
- 実際に動くものと宣言が一致する

---

## 使い方

### flake の入力に追加する

```nix
{
  inputs.memory-tencentdb-nix.url = "github:kuro1981/memory-tencentdb-nix";
}
```

### overlay として使う

```nix
pkgs = import nixpkgs {
  inherit system;
  overlays = [ memory-tencentdb-nix.overlays.default ];
};
# → pkgs.memory-tencentdb
```

### 直接ビルドする

```bash
nix build github:kuro1981/memory-tencentdb-nix
ls result/bin
```

公開される実行ファイル:

| コマンド | 用途 |
| --- | --- |
| `read-local-memory` | ローカルメモリの読み出し |
| `export-tencent-vdb` | ベクタ DB のエクスポート |
| `migrate-sqlite-to-tcvdb` | SQLite から TencentDB VectorDB への移行 |

---

## 更新

`.github/workflows/update.yml` が毎日 00:00 UTC に npm レジストリを確認し、新しいバージョンがあれば PR を作成して auto-merge する。

手動で実行する場合:

```bash
./scripts/update.sh              # 最新版へ更新
./scripts/update.sh --check      # 更新の有無を確認するだけ（あれば exit 1）
./scripts/update.sh --version 1.0.1
```

`update.sh` は以下を自動で行う。

1. `package.nix` と `package.json` の version を書き換える
2. `package-lock.json` を再生成する
3. `npmDepsHash` を解決する（一度ビルドを失敗させ、`got:` の値を拾う）
4. `flake.lock` を更新する
5. ビルドと実行ファイルの露出を検証する

---

## メモ

- **node のバージョンは `nodejs_22` に固定している。** 上流の要求が `>=18` であり、nixpkgs 既定の node が上がって壊れることを避けるため。
- ラッパーは依存を引くだけなのでビルド対象を持たない（`dontNpmBuild = true`）。

---

## License

パッケージングのコードは MIT。上流パッケージのライセンスは上流に従う。

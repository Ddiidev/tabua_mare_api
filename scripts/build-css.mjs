import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { transform } from "lightningcss";
import { PurgeCSS } from "purgecss";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = join(root, "pages", "styles", "site.css");
const outputDir = join(root, "pages", "assets", "css");
const sharedTemplates = ["navbar.html", "footer.html"].map((file) =>
  join(root, "pages", file),
);
const bundles = {
  home: ["index.html"],
  docs: ["docs.html"],
  playground: ["playground.html"],
  dashboard: ["dashboard.html"],
  apoiar: ["apoiar.html"],
  legal: ["privacidade.html", "termos.html"],
  "rate-limit-test": ["rate_limit_test.html"],
};

const safelist = {
  standard: [
    /^active$/,
    /^current$/,
    /^is-/,
    /^language-/,
    /^plan-/,
    /^token$/,
  ],
  greedy: [/\.language-/],
};
const prismSafelist = {
  ...safelist,
  // Prism injeta classes no navegador; elas nao existem no HTML de build.
  greedy: [...safelist.greedy, /token/],
};

function runTailwind(output) {
  const cli = resolve(
    root,
    "node_modules/@tailwindcss/cli/dist/index.mjs",
  );

  return new Promise((accept, reject) => {
    const child = spawn(process.execPath, [cli, "-i", source, "-o", output], {
      cwd: root,
      stdio: "inherit",
    });
    child.once("error", reject);
    child.once("exit", (code) => {
      if (code === 0) accept();
      else reject(new Error(`Tailwind encerrou com codigo ${code}.`));
    });
  });
}

const temporaryDir = await mkdtemp(join(tmpdir(), "tabua-mare-css-"));
const compiledPath = join(temporaryDir, "site.css");

try {
  await mkdir(outputDir, { recursive: true });
  await runTailwind(compiledPath);
  const compiledCss = await readFile(compiledPath, "utf8");

  for (const [bundle, templates] of Object.entries(bundles)) {
    const contentFiles = [
      ...sharedTemplates,
      ...templates.map((file) => join(root, "pages", file)),
    ];
    const content = await Promise.all(
      contentFiles.map(async (file) => ({
        extension: "html",
        raw: await readFile(file, "utf8"),
      })),
    );
    const [purged] = await new PurgeCSS().purge({
      content,
      css: [{ raw: compiledCss }],
      fontFace: true,
      keyframes: true,
      safelist: ["docs", "playground"].includes(bundle) ? prismSafelist : safelist,
      variables: true,
    });
    const output = transform({
      code: Buffer.from(purged.css),
      filename: `${bundle}.css`,
      minify: true,
    }).code;
    const outputPath = join(outputDir, `${bundle}.css`);
    await writeFile(outputPath, output);
    console.log(`${basename(outputPath)}: ${output.byteLength} B`);
  }
} finally {
  await rm(temporaryDir, { force: true, recursive: true });
}

import { describe, it, expect } from "vitest";
import { loadRubric } from "../load-rubric";
import { mkdtempSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

describe("loadRubric", () => {
  it("loads a rubric by name", () => {
    const dir = mkdtempSync(join(tmpdir(), "rubrics-"));
    mkdirSync(join(dir, "rubrics"));
    writeFileSync(
      join(dir, "rubrics", "hello-world.md"),
      `---\nname: hello-world\nmax_iterations: 2\n---\n\n# Hello-world rubric\n\n1. A file exists.\n2. It contains text.\n`,
    );
    const rubric = loadRubric(join(dir, "rubrics"), "hello-world");
    expect(rubric.name).toBe("hello-world");
    expect(rubric.maxIterations).toBe(2);
    expect(rubric.body).toContain("Hello-world rubric");
  });

  it("throws if rubric does not exist", () => {
    const dir = mkdtempSync(join(tmpdir(), "rubrics-"));
    mkdirSync(join(dir, "rubrics"));
    expect(() => loadRubric(join(dir, "rubrics"), "nope")).toThrow(/nope/);
  });
});

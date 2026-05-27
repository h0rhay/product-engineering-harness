import { describe, it, expect } from "vitest";
import { parseArgs } from "../args";

describe("parseArgs", () => {
  it("parses required flags", () => {
    const result = parseArgs([
      "--workpiece", "owner/repo",
      "--goal", "do the thing",
      "--rubric", "hello-world",
    ]);
    expect(result).toEqual({
      workpiece: "owner/repo",
      goal: "do the thing",
      rubric: "hello-world",
    });
  });

  it("throws when --workpiece is missing", () => {
    expect(() => parseArgs(["--goal", "x", "--rubric", "hello-world"]))
      .toThrow(/workpiece/);
  });

  it("throws when --goal is missing", () => {
    expect(() => parseArgs(["--workpiece", "x", "--rubric", "hello-world"]))
      .toThrow(/goal/);
  });

  it("throws when --rubric is missing", () => {
    expect(() => parseArgs(["--workpiece", "x", "--goal", "y"]))
      .toThrow(/rubric/);
  });
});

export interface CloudRunArgs {
  workpiece: string;
  goal: string;
  rubric: string;
}

export function parseArgs(argv: string[]): CloudRunArgs {
  const get = (flag: string): string | undefined => {
    const idx = argv.indexOf(flag);
    return idx >= 0 && idx + 1 < argv.length ? argv[idx + 1] : undefined;
  };
  const workpiece = get("--workpiece");
  const goal = get("--goal");
  const rubric = get("--rubric");
  if (!workpiece) throw new Error("--workpiece is required (owner/repo)");
  if (!goal) throw new Error("--goal is required");
  if (!rubric) throw new Error("--rubric is required");
  return { workpiece, goal, rubric };
}

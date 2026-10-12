// The rules places.mjs applies to what it reads, kept apart from the database so they can be
// tested.

// A creature template that copies another for a difficulty or a test, as Alterac Valley's
// "Alliance Sentinel (1)" and "Commander Dardosh <old> (1)" do. Named as a source, it showed on a
// page as "Dropped by Alliance Sentinel (1)".
export function isTemplateCopy(name) {
  return / \(\d+\)$/.test(name ?? "") || /<old>/i.test(name ?? "");
}

/// Deterministic Sudoku generation and solving for Game Station.
///
/// Every puzzle is a pure function of its ID, so the same ID yields the same
/// grid on every platform, in every release, with nothing stored and nothing
/// fetched. Saved progress records puzzle IDs rather than grids, so that
/// property is load-bearing rather than a nicety — see `PLAN.md` §3.1.
///
/// This package deliberately imports neither Flutter nor `dart:io`: it is
/// data in, data out, which keeps its tests fast enough to fuzz thousands of
/// seeds per run.
library;

export 'src/generator_version.dart';

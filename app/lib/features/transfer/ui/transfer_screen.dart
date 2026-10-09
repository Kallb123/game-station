// The screen behind Settings > Move players (`PLAN-transfer.md` §3.4).
//
// A parent's screen, reached from Settings rather than the player picker, but
// built to the same rules as the rest of the app: a big button per choice,
// one short line per outcome, and never a word of the underlying error
// (`AGENTS.md`). Every failure here collapses to a fixed sentence, because the
// only thing a parent can do with `PathAccessException: errno = 13` is be
// worried by it.
//
// Nothing here does I/O while building. The platform edge
// (`transferFilesProvider`) is read when a button is tapped, so the layout
// sweep can pump this route without a channel or `path_provider` behind it.

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/ui/avatars.dart';
import '../../../core/ui/big_button.dart';
import '../../../core/ui/layout.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/tokens.dart';
import '../data/providers.dart';
import '../data/transfer_codec.dart';
import '../data/transfer_files.dart';
import '../data/transfer_service.dart';

/// The screen's own name, and the label of the Settings row that opens it.
const String transferTitle = 'Move players';

/// The heading over the buttons that write a file.
const String saveSectionLabel = 'Save to a file';

/// The button that writes every player to one file.
const String everyoneLabel = 'Everyone';

/// The heading over the button that reads a file.
const String loadSectionLabel = 'Load from a file';

/// The button that starts loading: the system picker, or the list of files.
const String chooseFileLabel = 'Choose a file';

/// What a successful save says, with [where] as the platform described it: a
/// folder, or the name the parent typed into the system dialog.
String savedMessage(String where) => 'Saved to $where';

/// Said for any save that threw. Never the error itself.
const String saveFailedMessage = "Couldn't save the file.";

/// Said for any load that threw after the parent pressed *Load*.
const String loadFailedMessage = "Couldn't load the file.";

/// Said when the file's own problem was not a version one, and for any file
/// that could not be read at all: from the parent's side they are the same
/// answer, "this is not something to load".
const String notAPlayersFileMessage = "That file isn't a players file.";

/// One sentence for each reason a file is refused. Exhaustive over
/// [TransferProblem], so a new reason cannot reach the screen unworded.
String refusalMessage(TransferProblem problem) => switch (problem) {
  TransferProblem.notAPlayersFile => notAPlayersFileMessage,
  TransferProblem.fromNewerApp =>
    'That file is from a newer version of Zibo Games. Update this one first.',
  TransferProblem.differentPuzzleVersion =>
    'That file is from a different version of Zibo Games.',
};

/// The heading of the list of files on a folder platform.
const String pickFileTitle = 'Pick a file';

/// What the folder list says when it has nothing to offer.
///
/// The folder's path is not known from the entry list, so this names it the
/// way a parent finds it: the Files app on iOS, Downloads elsewhere
/// (`PLAN-transfer.md` §3.3).
String noFilesMessage(TargetPlatform platform) => platform == TargetPlatform.iOS
    ? 'Put a players file in the Zibo Games folder in the Files app.'
    : 'Put a players file in the Zibo Games folder in Downloads.';

/// The title of the confirmation page.
const String confirmTitle = 'Load players';

/// The switch that decides whether this device's settings are overwritten.
const String copySettingsLabel = 'Copy settings too';

/// The button that does the loading.
const String loadLabel = 'Load';

/// "Replaces Ana", under a player whose `createdAt` matches a local one.
String replacesMessage(String name) => 'Replaces $name';

/// What a successful load says.
String loadedMessage(int count) =>
    count == 1 ? 'Loaded 1 player' : 'Loaded $count players';

/// Save players to a file, or load them from one.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  /// True while a file is being written, picked or read. Disables every button:
  /// a second tap on *Everyone* while the system dialog is open would stack a
  /// second dialog behind the first.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = ref.watch(progressRepositoryProvider).profiles;
    final onPressed = _busy ? null : _save;

    return ScreenScaffold(
      title: transferTitle,
      child: ContentWidthCap(
        child: ListView(
          children: [
            _Heading(saveSectionLabel, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            for (final profile in profiles) ...[
              AvatarTheme(
                avatar: profile.avatar,
                child: BigButton(
                  icon: avatarIcon(profile.avatar),
                  label: profile.name,
                  onPressed: onPressed == null
                      ? null
                      : () => _save(profileId: profile.id),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            BigButton(
              icon: Icons.groups,
              label: everyoneLabel,
              onPressed: onPressed,
            ),
            const SizedBox(height: AppSpacing.xl),
            _Heading(loadSectionLabel, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            BigButton(
              icon: Icons.folder_open,
              label: chooseFileLabel,
              onPressed: _busy ? null : _load,
            ),
          ],
        ),
      ),
    );
  }

  /// Writes [profileId]'s file, or everyone's when it is null.
  Future<void> _save({String? profileId}) async {
    if (_busy) return;
    setState(() => _busy = true);

    final service = ref.read(transferServiceProvider);
    final files = ref.read(transferFilesProvider);
    String? message;
    try {
      final text = await service.exportText(profileId: profileId);
      final where = await files.write(
        service.suggestedFileName(profileId: profileId),
        text,
      );
      // Null is a dismissed dialog: the parent changed their mind, which is
      // an answer and not a failure, so nothing is said.
      if (where != null) message = savedMessage(where);
    } on Object {
      message = saveFailedMessage;
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) _say(message);
  }

  /// Picks a file, reads it, and opens the confirmation page for it.
  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);

    final service = ref.read(transferServiceProvider);
    final files = ref.read(transferFilesProvider);

    // Everything up to the confirmation page changes nothing on the device, so
    // every failure on the way there is the same sentence and the same state.
    String? refusal;
    TransferBundle? bundle;
    List<ImportCandidate> candidates = const [];
    try {
      final text = await _chooseText(files);
      if (text != null) {
        bundle = service.read(text);
        candidates = service.preview(bundle);
      }
    } on TransferException catch (error) {
      refusal = refusalMessage(error.problem);
    } on Object {
      refusal = notAPlayersFileMessage;
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (refusal != null) {
      _say(refusal);
      return;
    }
    if (bundle == null) return;

    final outcome = await Navigator.of(context).push<_LoadOutcome>(
      MaterialPageRoute(
        builder: (context) =>
            _ConfirmLoadScreen(bundle: bundle!, candidates: candidates),
      ),
    );
    if (!mounted || outcome == null) return;
    _say(
      outcome.loaded == null
          ? loadFailedMessage
          : loadedMessage(outcome.loaded!),
    );
  }

  /// The text of the file the parent chose, or null if they chose none.
  Future<String?> _chooseText(TransferFiles files) async {
    if (files.usesSystemPicker) return files.pickAndRead();

    List<TransferFileEntry> entries;
    try {
      entries = await files.listFiles();
    } on Object {
      // A folder that cannot be listed is, to the parent, a folder with
      // nothing in it, and the dialog says where to put one.
      entries = const [];
    }
    if (!mounted) return null;

    final chosen = await showDialog<TransferFileEntry>(
      context: context,
      builder: (context) => _FilePickerDialog(entries: entries),
    );
    return chosen == null ? null : files.readFile(chosen);
  }

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// A section heading, announced as one.
class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: style));
}

/// The files in the folder, newest first, one big row each.
class _FilePickerDialog extends StatelessWidget {
  const _FilePickerDialog({required this.entries});

  final List<TransferFileEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text(pickFileTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: entries.isEmpty
            ? SingleChildScrollView(
                child: Text(
                  noFilesMessage(defaultTargetPlatform),
                  style: theme.textTheme.bodyLarge,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in entries)
                    ListTile(
                      minTileHeight: AppTapTargets.primary,
                      title: Text(entry.name),
                      subtitle: Text(_formatDate(entry.modified.toLocal())),
                      onTap: () => Navigator.of(context).pop(entry),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  /// `2026-10-08 09:05`. Digits only, so it reads the same in any language the
  /// device is set to and needs no locale data.
  static String _formatDate(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }
}

/// What the confirmation page was closed with. [loaded] is how many players
/// were loaded, or null when loading threw.
class _LoadOutcome {
  const _LoadOutcome(this.loaded);

  final int? loaded;
}

/// The players in a readable file, and the choice of which to load.
///
/// A pushed page rather than a dialog: a file of four players, each with a
/// name that wraps at 200% text scale and a second line under it, is taller
/// than any dialog a 360x640 phone can show, and a page scrolls like every
/// other screen here.
///
/// It does the loading itself rather than returning the choice, so its *Load*
/// button can be disabled while the files are being written and a second tap
/// cannot start a second import.
class _ConfirmLoadScreen extends ConsumerStatefulWidget {
  const _ConfirmLoadScreen({required this.bundle, required this.candidates});

  final TransferBundle bundle;
  final List<ImportCandidate> candidates;

  @override
  ConsumerState<_ConfirmLoadScreen> createState() => _ConfirmLoadScreenState();
}

class _ConfirmLoadScreenState extends ConsumerState<_ConfirmLoadScreen> {
  /// File ids of the players that are ticked. All of them, to begin with: a
  /// parent who opened a file meant to load it.
  late final Set<String> _chosen = {
    for (final candidate in widget.candidates) candidate.incoming.id,
  };

  /// Whether this device's settings are overwritten. A file of everyone is a
  /// whole tablet moving and takes its settings with it; a file of some players
  /// leaves them alone, so a child moving onto a sibling's tablet cannot change
  /// its parental controls (`PLAN-transfer.md` §1).
  late bool _includeSettings = widget.bundle.everyone;

  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: confirmTitle,
      child: ContentWidthCap(
        child: ListView(
          children: [
            for (final candidate in widget.candidates)
              _CandidateTile(
                candidate: candidate,
                checked: _chosen.contains(candidate.incoming.id),
                onChanged: _busy
                    ? null
                    : (checked) => setState(() {
                        if (checked) {
                          _chosen.add(candidate.incoming.id);
                        } else {
                          _chosen.remove(candidate.incoming.id);
                        }
                      }),
              ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              value: _includeSettings,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _includeSettings = value),
              minTileHeight: AppTapTargets.primary,
              minVerticalPadding: AppSpacing.md,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
              ),
              title: Text(
                copySettingsLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              secondary: const Icon(Icons.settings, size: AppIconSizes.large),
            ),
            const SizedBox(height: AppSpacing.xl),
            BigButton(
              icon: Icons.download,
              label: loadLabel,
              onPressed: _chosen.isEmpty || _busy ? null : _apply,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apply() async {
    setState(() => _busy = true);

    final service = ref.read(transferServiceProvider);
    final count = _chosen.length;
    int? loaded = count;
    try {
      await service.apply(
        widget.bundle,
        fileProfileIds: Set.of(_chosen),
        includeSettings: _includeSettings,
      );
    } on Object {
      loaded = null;
    }

    if (!mounted) return;
    Navigator.of(context).pop(_LoadOutcome(loaded));
  }
}

/// One player in the file: their picture, their name, a tick, and which local
/// player loading them would replace.
///
/// A [CheckboxListTile] so the whole row toggles, as the settings switches do.
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.checked,
    required this.onChanged,
  });

  final ImportCandidate candidate;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final player = candidate.incoming;
    final replaces = candidate.replaces;

    return AvatarTheme(
      avatar: player.avatar,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);

          return CheckboxListTile(
            value: checked,
            onChanged: onChanged == null
                ? null
                : (value) => onChanged!(value ?? false),
            minTileHeight: AppTapTargets.primary,
            minVerticalPadding: AppSpacing.md,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
            ),
            controlAffinity: ListTileControlAffinity.trailing,
            secondary: Icon(
              avatarIcon(player.avatar),
              size: AppIconSizes.large,
              color: theme.colorScheme.primary,
            ),
            title: Text(player.name, style: theme.textTheme.titleMedium),
            subtitle: replaces == null
                ? null
                : Text(replacesMessage(replaces.name)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
          );
        },
      ),
    );
  }
}

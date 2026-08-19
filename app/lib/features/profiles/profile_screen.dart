import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/progress_repository.dart';
import '../../core/storage/providers.dart';
import '../../core/storage/save_data.dart';
import '../../core/ui/avatars.dart';
import '../../core/ui/big_button.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/screen_scaffold.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';

/// The label on the control that makes a new profile, here rather than at each
/// use so a test names the same string the screen draws.
const String addProfileLabel = 'Add a player';

/// Who is playing, and how that is changed.
///
/// One button per profile, each with the profile's own picture and colour, and
/// one more to add another. Tapping a profile is the whole point of the screen,
/// so it is the largest thing on it; renaming, changing the picture and
/// deleting sit behind one edit control per row, where a mis-tap cannot lose a
/// child's games.
///
/// A single column rather than the grid in PLAN-phase-1.md §6: a `GridView`
/// tile has a fixed aspect ratio, so at 200% text scale a name wraps inside a
/// box that cannot grow and is clipped. There are at most a handful of
/// profiles, so scrolling one column costs nothing and nothing is ever cut off.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(progressRepositoryProvider);
    final profiles = repository.profiles;
    final activeId = repository.activeProfile.id;

    return ScreenScaffold(
      title: 'Players',
      child: ContentWidthCap(
        child: ListView.separated(
          // The add control is the last row rather than a floating button:
          // it then scrolls with the list and cannot cover the last profile.
          itemCount: profiles.length + 1,
          separatorBuilder: (context, index) =>
              const SizedBox(height: AppSpacing.lg),
          itemBuilder: (context, index) {
            if (index == profiles.length) return const _AddProfileButton();

            final profile = profiles[index];
            return _ProfileRow(
              profile: profile,
              selected: profile.id == activeId,
              // The repository refuses to delete the last profile
              // (`progress_repository.dart`); hiding the control as well
              // means a child never taps something that then says no.
              canDelete: profiles.length > 1,
            );
          },
        ),
      ),
    );
  }
}

/// One profile: a big button that selects it, and a way to change it.
class _ProfileRow extends ConsumerWidget {
  const _ProfileRow({
    required this.profile,
    required this.selected,
    required this.canDelete,
  });

  final Profile profile;
  final bool selected;
  final bool canDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: _AvatarTheme(
            avatar: profile.avatar,
            child: BigButton(
              icon: avatarIcon(profile.avatar),
              label: profile.name,
              selected: selected,
              onPressed: () => _select(context, ref),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        IconButton(
          onPressed: () => _edit(context, ref),
          icon: const Icon(Icons.edit, size: AppIconSizes.large),
          // Named after the profile, so eight identical "Edit" buttons are
          // eight different controls to a screen reader.
          tooltip: 'Change ${profile.name}',
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  void _select(BuildContext context, WidgetRef ref) {
    ref.read(progressRepositoryProvider).selectProfile(profile.id);
    // Straight back to the home screen. Picking a player is the question this
    // screen was opened to answer, and a child who has answered it should not
    // have to find the back arrow to start playing.
    Navigator.of(context).pop();
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(progressRepositoryProvider);
    final result = await _showProfileEditor(
      context,
      title: 'Change ${profile.name}',
      confirmLabel: 'Save',
      initialName: profile.name,
      initialAvatar: profile.avatar,
      canDelete: canDelete,
    );

    switch (result) {
      case null:
        return;
      case _EditorSave(:final name, :final avatar):
        // Two mutations, one write: both land in memory before the debounce in
        // `progress_repository.dart` expires.
        repository.renameProfile(profile.id, name);
        repository.setProfileAvatar(profile.id, avatar);
      case _EditorDelete():
        if (!context.mounted) return;
        if (await _confirmDelete(context, profile.name)) {
          repository.deleteProfile(profile.id);
        }
    }
  }
}

/// The control that makes another profile.
class _AddProfileButton extends ConsumerWidget {
  const _AddProfileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BigButton(
      icon: Icons.add,
      label: addProfileLabel,
      onPressed: () => _create(context, ref),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(progressRepositoryProvider);
    final result = await _showProfileEditor(
      context,
      title: 'New player',
      confirmLabel: 'Create',
      initialName: '',
      initialAvatar: _unusedAvatar(repository.profiles),
      canDelete: false,
    );
    if (result is! _EditorSave) return;

    // An empty name becomes `Player n` in the repository rather than a
    // validation error here: a child who taps *Create* without typing gets a
    // profile (`progress_repository.dart`).
    repository.createProfile(name: result.name, avatar: result.avatar);
    // Creating makes the new profile the active one, so the same reasoning as
    // selecting applies — the screen has answered its question.
    if (context.mounted) Navigator.of(context).pop();
  }
}

/// The first picture no profile is using, or the first of all when every
/// picture is taken.
///
/// A counter over the enum rather than a random pick (PLAN-phase-1.md §1), and
/// it means the second profile on a device looks different from the first
/// without anyone choosing.
AvatarId _unusedAvatar(List<Profile> profiles) {
  final taken = profiles.map((profile) => profile.avatar).toSet();
  return AvatarId.values.firstWhere(
    (avatar) => !taken.contains(avatar),
    orElse: () => AvatarId.values.first,
  );
}

/// Recolours [child] as [avatar], the way the home screen recolours its two
/// cards.
///
/// The scheme is derived from the swatch rather than applied as a background
/// colour, so the label and the icon get a foreground from the same tonal
/// palette (`theme.dart`).
class _AvatarTheme extends StatelessWidget {
  const _AvatarTheme({required this.avatar, required this.child});

  final AvatarId avatar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        colorScheme: AppTheme.roleScheme(
          avatarColor(avatar, theme.brightness),
          theme.brightness,
        ),
      ),
      child: child,
    );
  }
}

// --- the editor -------------------------------------------------------------

/// What [_ProfileEditor] was closed with. Null means it was cancelled.
sealed class _EditorResult {}

/// Keep these values.
class _EditorSave implements _EditorResult {
  _EditorSave(this.name, this.avatar);

  final String name;
  final AvatarId avatar;
}

/// Get rid of this profile, once the child has been asked again.
class _EditorDelete implements _EditorResult {}

/// Asks for a name and a picture.
Future<_EditorResult?> _showProfileEditor(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required String initialName,
  required AvatarId initialAvatar,
  required bool canDelete,
}) => showDialog<_EditorResult>(
  context: context,
  builder: (context) => _ProfileEditor(
    title: title,
    confirmLabel: confirmLabel,
    initialName: initialName,
    initialAvatar: initialAvatar,
    canDelete: canDelete,
  ),
);

/// The name field and the picture grid, for both creating and changing.
///
/// One dialog for both, because they ask the same two questions. The delete
/// action lives here rather than on the row for the same reason: the row is
/// what a child taps to play, and everything that changes a profile is one
/// deliberate step away from it.
class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.initialAvatar,
    required this.canDelete,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final AvatarId initialAvatar;
  final bool canDelete;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late AvatarId _avatar = widget.initialAvatar;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      // Scrolls, because the dialog cannot grow past the screen and the picture
      // grid plus a keyboard at 200% text scale is taller than a phone.
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              maxLength: maxProfileNameLength,
              decoration: const InputDecoration(
                labelText: 'Name',
                // A "3/12" counter is nothing a young child can act on, and
                // the field stops accepting text at the cap anyway.
                counterText: '',
              ),
              // Enter finishes the dialog, so a parent typing a name never has
              // to reach for the button.
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Picture', style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final avatar in AvatarId.values)
                  _AvatarChoice(
                    avatar: avatar,
                    selected: avatar == _avatar,
                    onPressed: () => setState(() => _avatar = avatar),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (widget.canDelete)
          TextButton(
            onPressed: () => Navigator.of(context).pop(_EditorDelete()),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: Text(widget.confirmLabel)),
      ],
    );
  }

  void _save() => Navigator.of(context).pop(_EditorSave(_name.text, _avatar));
}

/// One picture to choose from.
///
/// Selection is a border and a filled background as well as the colour, so a
/// player who cannot tell two swatches apart can still see which one is theirs
/// (`tokens.dart`).
class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.avatar,
    required this.selected,
    required this.onPressed,
  });

  final AvatarId avatar;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _AvatarTheme(
      avatar: avatar,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;

          return IconButton(
            onPressed: onPressed,
            tooltip: avatarLabel(avatar),
            iconSize: AppIconSizes.large,
            // The flag goes inside the button, as it does in `BigButton`: put
            // around it, it becomes a second semantics node that a screen
            // reader announces beside the button rather than as part of it.
            icon: Semantics(
              selected: selected,
              child: Icon(avatarIcon(avatar)),
            ),
            style: IconButton.styleFrom(
              minimumSize: const Size(AppTapTargets.min, AppTapTargets.min),
              foregroundColor: selected
                  ? colors.onPrimaryContainer
                  : colors.primary,
              backgroundColor: selected ? colors.primaryContainer : null,
              side: BorderSide(
                color: selected ? colors.onPrimaryContainer : colors.outline,
                width: selected ? AppBorders.selected : AppBorders.hairline,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Asks once more before a profile's games go.
///
/// A second dialog rather than an undo: undo is a control a child has to
/// notice and understand within a few seconds, and there is nothing to notice
/// it on once the picker has closed.
Future<bool> _confirmDelete(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $name?'),
      content: const Text('Their games and scores will be gone.'),
      actions: [
        // Losing the games is the outcome that cannot be undone, so keeping
        // them is the emphasised button: the child who taps the obvious one
        // ends up where the fewest things are lost.
        //
        // "Keep" rather than "Cancel" for the same reason — at this point the
        // two buttons are a choice between two outcomes, and naming both is
        // what makes the safe one recognisable without reading the sentence
        // above them.
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

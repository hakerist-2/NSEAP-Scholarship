import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';
import 'package:nseapscholarship/utils/error_messages.dart';

String adminLabel(String value) {
  // latest_assessment_form accepts assessment form OR certificate of enrolment.
  if (value == 'latest_assessment_form') {
    return 'Assessment Form / Certificate of Enrolment';
  }
  final normalized = value == 'verified' ? 'approved' : value;
  return normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String adminDateLabel(DateTime? value, {bool withTime = false}) {
  if (value == null) return 'Not set';
  String two(int number) => number.toString().padLeft(2, '0');
  final date = '${two(value.month)}/${two(value.day)}/${value.year}';
  return withTime ? '$date ${two(value.hour)}:${two(value.minute)}' : date;
}

/// Toggles bulk-selection controls with consistent admin styling.
class AdminSelectionButton extends StatelessWidget {
  const AdminSelectionButton({
    required this.selectionMode,
    required this.onPressed,
    super.key,
  });

  final bool selectionMode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        selectionMode ? Icons.close_rounded : Icons.checklist_rounded,
        size: 18,
      ),
      label: Text(selectionMode ? 'Cancel selection' : 'Select'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: AppColors.borderLight, width: 1.2),
        foregroundColor: AppColors.textPrimary,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// Shared export format for admin tables.
enum AdminExportFormat { pdf, csv }

/// Consistent "Exports" dropdown button with PDF and CSV options.
class AdminExportDropdown extends StatelessWidget {
  const AdminExportDropdown({
    required this.onExportPdf,
    required this.onExportCsv,
    this.enabled = true,
    this.exporting = false,
    this.count,
    this.label = 'Exports',
    super.key,
  });

  final VoidCallback onExportPdf;
  final VoidCallback onExportCsv;
  final bool enabled;
  final bool exporting;
  final int? count;
  final String label;

  String get _label {
    if (exporting) return 'Exporting...';
    if (count != null && count! > 0) return '$label ($count)';
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final canInteract = enabled && !exporting;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.white),
        elevation: WidgetStateProperty.all(8),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: canInteract ? onExportPdf : null,
          leadingIcon: const Icon(
            Icons.picture_as_pdf_outlined,
            color: NseapColors.error,
            size: 18,
          ),
          child: const Text('Export as PDF', style: TextStyle(fontSize: 13.5)),
        ),
        MenuItemButton(
          onPressed: canInteract ? onExportCsv : null,
          leadingIcon: const Icon(
            Icons.table_view_outlined,
            color: NseapColors.primary,
            size: 18,
          ),
          trailingIcon: const Icon(Icons.copy_all_outlined, size: 16),
          child: const Text('Export as CSV', style: TextStyle(fontSize: 13.5)),
        ),
      ],
      builder: (context, controller, child) => FilledButton.icon(
        onPressed: canInteract
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        icon: exporting
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.file_download_outlined, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Icon(
              controller.isOpen
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
            ),
          ],
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

/// Displays a responsive page title and optional action.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    required this.title,
    this.action,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: Color(0xFF0F172A),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                height: 1.1,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
            ],
          ],
        );
        if (action == null) return titleWidget;
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [titleWidget, const SizedBox(height: 14), action!],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleWidget),
            const SizedBox(width: 16),
            action!,
          ],
        );
      },
    );
  }
}

/// Builds the compact rounded field chrome shared by search bars and filters.
InputDecoration adminFieldDecoration({String? hint, IconData? prefixIcon}) {
  const radius = BorderRadius.all(Radius.circular(12));
  OutlineInputBorder border([
    Color color = AppColors.borderLight,
    double width = 1.2,
  ]) => OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      fontSize: 13,
      color: AppColors.textTertiary,
      fontWeight: FontWeight.w400,
    ),
    prefixIcon: prefixIcon == null
        ? null
        : Icon(prefixIcon, size: 18, color: AppColors.textSecondary),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    constraints: const BoxConstraints(minHeight: 40),
    border: border(),
    enabledBorder: border(),
    focusedBorder: border(AppColors.primary, 1.8),
  );
}

/// Compact search input used by admin toolbars and the shell header.
class AdminSearchField extends StatefulWidget {
  const AdminSearchField({
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.controller,
    super.key,
  });

  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  bool _focused = false;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: AppDurations.hover,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      boxShadow: _focused
          ? [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.12),
                blurRadius: 0,
                spreadRadius: 3,
              ),
            ]
          : null,
    ),
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      onChanged: (v) {
        widget.onChanged?.call(v);
        setState(() {});
      },
      onSubmitted: widget.onSubmitted,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      textInputAction: TextInputAction.search,
      decoration:
          adminFieldDecoration(
            hint: widget.hint,
            prefixIcon: Icons.search_rounded,
          ).copyWith(
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged?.call('');
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: AppColors.textTertiary,
                    tooltip: 'Clear',
                  )
                : null,
          ),
    ),
  );
}

/// Provides a responsive search field with an optional filter control.
class AdminToolbar extends StatelessWidget {
  const AdminToolbar({
    required this.onSearch,
    this.filter,
    this.hint = 'Search',
    super.key,
  });

  final ValueChanged<String> onSearch;
  final Widget? filter;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = AdminSearchField(hint: hint, onChanged: onSearch);
        if (filter == null) return search;
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [search, const SizedBox(height: 10), filter!],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            SizedBox(width: 190, child: filter),
          ],
        );
      },
    );
  }
}

/// Renders a consistently colored badge for an administrative status.
class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    // Normalize legacy 'verified' to 'approved' for display.
    final normalizedStatus = status == 'verified' ? 'approved' : status;
    final tone = switch (normalizedStatus) {
      'active' ||
      'approved' ||
      'received' ||
      'scholar' ||
      'published' => NseapStatusTone.success,
      'rejected' ||
      'cancelled' ||
      'cancelled_submission' ||
      'terminated' ||
      'suspended' ||
      'needs_revision' => NseapStatusTone.error,
      'graduated' || 'completed' || 'closed' => NseapStatusTone.success,
      'scheduled' ||
      'submitted' ||
      'pending' ||
      'under_review' => NseapStatusTone.warning,
      _ => NseapStatusTone.neutral,
    };
    return NseapStatusBadge(label: adminLabel(normalizedStatus), tone: tone);
  }
}

/// Maps a future to the standard admin loading, error, empty, or data view.
class AdminAsyncView<T> extends StatelessWidget {
  const AdminAsyncView({
    required this.future,
    required this.isEmpty,
    required this.builder,
    required this.onRetry,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage = 'Records will appear here when they are available.',
    super.key,
  });

  final Future<T> future;
  final bool Function(T data) isEmpty;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData) {
          return const AdminStatePanel.loading();
        }
        if (snapshot.hasError) {
          return AdminStatePanel.error(
            message: readableAdminError(snapshot.error),
            onRetry: onRetry,
          );
        }
        final data = snapshot.requireData;
        if (isEmpty(data)) {
          return AdminStatePanel.empty(
            title: emptyTitle,
            message: emptyMessage,
          );
        }
        return builder(context, data);
      },
    );
  }
}

/// Displays standardized loading, empty, and error feedback for admin pages.
class AdminStatePanel extends StatelessWidget {
  const AdminStatePanel._({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    this.onRetry,
    super.key,
  });

  const AdminStatePanel.loading({Key? key})
    : this._(
        key: key,
        icon: Icons.hourglass_empty_rounded,
        title: 'Loading records',
        message: 'Please wait while the latest data is retrieved.',
        loading: true,
      );

  const AdminStatePanel.empty({
    String title = 'No records found',
    String message = 'Try changing your search or filter.',
    Key? key,
  }) : this._(
         key: key,
         icon: Icons.inbox_outlined,
         title: title,
         message: message,
       );

  const AdminStatePanel.error({
    required String message,
    required VoidCallback onRetry,
    Key? key,
  }) : this._(
         key: key,
         icon: Icons.cloud_off_outlined,
         title: 'Unable to load data',
         message: message,
         onRetry: onRetry,
       );

  final IconData icon;
  final String title;
  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox.shrink();
    }

    final isError = icon == Icons.cloud_off_outlined;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isError ? AppColors.errorLight : AppColors.primaryLight,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isError
                      ? AppColors.error.withValues(alpha: 0.14)
                      : AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Icon(
                icon,
                size: 30,
                color: isError ? AppColors.error : AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                height: 40,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows paginated records as cards on narrow screens and a table otherwise.
class AdminResponsiveCollection<T> extends StatefulWidget {
  const AdminResponsiveCollection({
    required this.items,
    required this.columns,
    required this.cells,
    required this.cardBuilder,
    this.isSelected,
    this.onSelectionChanged,
    super.key,
  });

  final List<T> items;
  final List<DataColumn> columns;
  final List<DataCell> Function(T item) cells;
  final Widget Function(BuildContext context, T item) cardBuilder;
  final bool Function(T item)? isSelected;
  final void Function(T item, bool selected)? onSelectionChanged;

  @override
  State<AdminResponsiveCollection<T>> createState() =>
      _AdminResponsiveCollectionState<T>();
}

class _AdminResponsiveCollectionState<T>
    extends State<AdminResponsiveCollection<T>> {
  static const _pageSize = 15;
  int _page = 0;

  @override
  void didUpdateWidget(covariant AdminResponsiveCollection<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lastPage = widget.items.isEmpty
        ? 0
        : (widget.items.length - 1) ~/ _pageSize;
    if (_page > lastPage) _page = lastPage;
  }

  @override
  Widget build(BuildContext context) {
    final start = _page * _pageSize;
    final end = math.min(start + _pageSize, widget.items.length);
    final pageItems = widget.items.sublist(start, end);

    return LayoutBuilder(
      builder: (context, constraints) {
        final collection = constraints.maxWidth < 760
            ? ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pageItems.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = pageItems[index];
                  final card = widget.cardBuilder(context, item);
                  if (widget.onSelectionChanged == null) return card;
                  final selected = widget.isSelected?.call(item) == true;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: selected,
                        onChanged: (value) =>
                            widget.onSelectionChanged!(item, value ?? false),
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Expanded(child: card),
                    ],
                  );
                },
              )
            : Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderLight),
                  boxShadow: AppElevation.shadowXs,
                ),
                clipBehavior: Clip.antiAlias,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFF8FAFC),
                      ),
                      headingRowHeight: 44,
                      dataRowMinHeight: 56,
                      dataRowMaxHeight: 56,
                      horizontalMargin: 12,
                      columnSpacing: 14,
                      dividerThickness: 1,
                      headingTextStyle: const TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                      dataTextStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1B2530),
                      ),
                      columns: widget.columns,
                      rows: pageItems.map((item) {
                        final selected = widget.isSelected?.call(item) == true;
                        return DataRow(
                          selected: selected,
                          color: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return AppColors.primary.withValues(alpha: 0.06);
                            }
                            if (states.contains(WidgetState.hovered)) {
                              return AppColors.surfaceContainer;
                            }
                            return null;
                          }),
                          onSelectChanged: widget.onSelectionChanged == null
                              ? null
                              : (value) => widget.onSelectionChanged!(
                                  item,
                                  value ?? false,
                                ),
                          cells: widget.cells(item),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              collection,
              if (widget.items.length > _pageSize) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${start + 1}–$end of ${widget.items.length}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Previous page',
                            onPressed: _page == 0
                                ? null
                                : () => setState(() => _page--),
                            icon: const Icon(Icons.chevron_left_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: const BorderSide(
                                color: AppColors.borderLight,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Next page',
                            onPressed: end >= widget.items.length
                                ? null
                                : () => setState(() => _page++),
                            icon: const Icon(Icons.chevron_right_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Displays a record summary used by responsive admin collections.
class AdminRecordCard extends StatefulWidget {
  const AdminRecordCard({
    required this.title,
    required this.subtitle,
    required this.fields,
    this.status,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String subtitle;
  final Map<String, String> fields;
  final String? status;
  final List<Widget> actions;

  @override
  State<AdminRecordCard> createState() => _AdminRecordCardState();
}

class _AdminRecordCardState extends State<AdminRecordCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppDurations.hover,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.borderLight,
          ),
          boxShadow: _hovered ? AppElevation.shadowMd : AppElevation.shadowXs,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.status != null) AdminStatusChip(widget.status!),
              ],
            ),
            const Divider(height: 24, color: AppColors.borderLight),
            ...widget.fields.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11.5,
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: Color(0xFF1B2530),
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: widget.actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// Converts an exception into a short message suitable for admin UI feedback.
String readableAdminError(Object? error) {
  return readableError(error);
}

/// Shows a standardized success or error message in the admin interface.
void showAdminMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  showNseapMessage(context, message, error: error);
}

/// Requests confirmation before an administrative action proceeds.
Future<bool> confirmAdminAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.5,
              fontSize: 13.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

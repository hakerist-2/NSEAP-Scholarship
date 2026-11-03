import 'package:flutter/material.dart';
import 'nseap_status_badge.dart';

/// Generic white card wrapping a DataTable with header + optional action.
class NseapTableCard extends StatelessWidget {
  const NseapTableCard({
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.rows,
    this.action,
    this.emptyMessage = 'No records yet.',
    super.key,
  });

  final String title;
  final String subtitle;
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final Widget? action;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 10), action!],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Icon(
                        Icons.inbox_outlined,
                        size: 20,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      emptyMessage,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final table = DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF8FAFC),
                  ),
                  headingRowHeight: 40,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 48,
                  horizontalMargin: 18,
                  columnSpacing: 20,
                  headingTextStyle: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                  dataTextStyle: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  dividerThickness: 1,
                  columns: columns,
                  rows: rows,
                );
                // horizontal scroll when narrow
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: table,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Recent application row model for convenience.
class RecentApplicationRow {
  const RecentApplicationRow({
    required this.name,
    required this.date,
    required this.status,
  });
  final String name;
  final String date;
  final String status;
}

class RecentScholarRow {
  const RecentScholarRow({
    required this.name,
    required this.program,
    required this.yearLevel,
    this.status = 'Active',
  });
  final String name;
  final String program;
  final String yearLevel;
  final String status;
}

List<DataRow> buildApplicationRows(List<RecentApplicationRow> data) => data
    .map(
      (r) => DataRow(
        cells: [
          DataCell(
            Text(
              r.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          DataCell(
            Text(
              r.date,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
            ),
          ),
          DataCell(NseapStatusBadge.fromStatus(r.status)),
        ],
      ),
    )
    .toList();

List<DataRow> buildScholarRows(List<RecentScholarRow> data) => data
    .map(
      (r) => DataRow(
        cells: [
          DataCell(
            Text(
              r.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          DataCell(Text(r.program)),
          DataCell(Text(r.yearLevel)),
          DataCell(NseapStatusBadge.fromStatus(r.status)),
        ],
      ),
    )
    .toList();

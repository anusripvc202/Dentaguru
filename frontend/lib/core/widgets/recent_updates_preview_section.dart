import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Standard maximum number of records shown in any dashboard Home / Overview
/// recent-activity preview section before clicking "View All".
const int kDashboardRecentPreviewLimit = 2;

/// Returns at most the latest [limit] items (defaults to 2) after sorting with
/// [compareDesc] when provided.
List<T> takeLatestPreviewRecords<T>(
  Iterable<T> source, {
  int limit = kDashboardRecentPreviewLimit,
  int Function(T a, T b)? compareDesc,
}) {
  final list = List<T>.from(source);
  if (compareDesc != null && list.length > 1) {
    list.sort(compareDesc);
  }
  if (list.length <= limit) return list;
  return list.sublist(0, limit);
}

/// Consistent section wrapper for recent updates across Admin, Doctor, Clinic,
/// and Patient dashboard Home pages.
///
/// Always displays:
/// - Section title (and optional total count badge) on the left
/// - **View All** action at the top-right
/// - Loading, error, or empty state when no records exist
/// - At most the latest 2 preview cards/rows
class RecentUpdatesPreviewSection extends StatelessWidget {
  final Key? sectionKey;
  final Key? viewAllKey;
  final Key? emptyStateKey;
  final String title;
  final int? totalCount;
  final IconData icon;
  final VoidCallback? onViewAll;
  final String viewAllLabel;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final List<Widget> previewChildren;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;

  const RecentUpdatesPreviewSection({
    super.key,
    this.sectionKey,
    this.viewAllKey,
    this.emptyStateKey,
    required this.title,
    this.totalCount,
    this.icon = Icons.update_rounded,
    this.onViewAll,
    this.viewAllLabel = 'View All',
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    required this.previewChildren,
    this.emptyIcon = Icons.inbox_outlined,
    required this.emptyTitle,
    this.emptySubtitle = '',
  });

  @override
  Widget build(BuildContext context) {
    final visibleChildren = previewChildren.length > kDashboardRecentPreviewLimit
        ? previewChildren.sublist(0, kDashboardRecentPreviewLimit)
        : previewChildren;

    return Container(
      key: sectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.gsNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: AppTheme.gsNavy),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.gsNavy,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (totalCount != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.gsNavy.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$totalCount',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.gsNavy,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onViewAll != null)
                TextButton(
                  key: viewAllKey,
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.gsNavy,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        viewAllLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.gsNavy,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppTheme.gsNavy,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (errorMessage != null && visibleChildren.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.gsRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.gsRed.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppTheme.gsRed, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                ],
              ),
            )
          else if (isLoading && visibleChildren.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: AppTheme.gsNavy),
                ),
              ),
            )
          else if (visibleChildren.isEmpty)
            Container(
              key: emptyStateKey,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.gsNavy.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(emptyIcon, size: 19, color: AppTheme.textMuted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          emptyTitle,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (emptySubtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            emptySubtitle,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textMuted,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: visibleChildren,
            ),
        ],
      ),
    );
  }
}

/// Compact, responsive recent-activity preview card for dashboard Home pages.
class RecentUpdatePreviewCard extends StatelessWidget {
  final Key? cardKey;
  final IconData leadingIcon;
  final Color leadingColor;
  final String title;
  final String subtitle;
  final String? metaLine;
  final String? statusLabel;
  final Color? statusColor;
  final Color? statusBgColor;
  final VoidCallback? onTap;

  const RecentUpdatePreviewCard({
    super.key,
    this.cardKey,
    this.leadingIcon = Icons.article_outlined,
    this.leadingColor = AppTheme.gsNavy,
    required this.title,
    required this.subtitle,
    this.metaLine,
    this.statusLabel,
    this.statusColor,
    this.statusBgColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStatusColor = statusColor ?? AppTheme.gsNavy;
    final effectiveStatusBg = statusBgColor ?? AppTheme.gsNavy.withValues(alpha: 0.10);

    return Container(
      key: cardKey,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gsNavy.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: leadingColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(leadingIcon, size: 19, color: leadingColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textMedium,
                        ),
                      ),
                      if (metaLine != null && metaLine!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          metaLine!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (statusLabel != null && statusLabel!.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: effectiveStatusBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLabel!,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: effectiveStatusColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

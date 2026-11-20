// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4
// design-system: DESIGN.md · mobile capture · warm paper / charcoal
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/design/scrapnote_tokens.dart';

class CaptureStatusPanel extends StatelessWidget {
  const CaptureStatusPanel({
    required this.status,
    required this.detail,
    required this.busy,
    required this.onRetry,
    required this.onAccount,
    super.key,
  });
  final String status;
  final String detail;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('capture-status-panel'),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: ScrapnoteTokens.rule)),
    ),
    padding: const EdgeInsets.only(left: 12),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ScrapnoteTokens.charcoal,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: ScrapnoteTokens.mutedInk,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox.square(
          dimension: 48,
          child: FButton.icon(
            key: const ValueKey('capture-retry'),
            variant: FButtonVariant.ghost,
            onPress: busy ? null : onRetry,
            semanticsLabel: '저장하고 업로드',
            child: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(FLucideIcons.refreshCw, size: 18),
          ),
        ),
        SizedBox.square(
          dimension: 48,
          child: FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: onAccount,
            semanticsLabel: '전송 내역과 계정',
            child: const Icon(FLucideIcons.list, size: 18),
          ),
        ),
      ],
    ),
  );
}

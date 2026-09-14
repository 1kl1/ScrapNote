import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../core/design/scrapnote_tokens.dart';

/// The only workspace shown until a local vault is connected.
class VaultOnboarding extends StatelessWidget {
  const VaultOnboarding({
    required this.onChooseVault,
    this.loading = false,
    super.key,
  });

  final VoidCallback onChooseVault;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ScrapnoteTokens.paper,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(ScrapnoteTokens.space5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '1 / 2',
                  style: TextStyle(
                    color: ScrapnoteTokens.signalOrange,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: ScrapnoteTokens.space3),
                const Text(
                  'Choose a local folder',
                  style: TextStyle(
                    color: ScrapnoteTokens.charcoal,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: ScrapnoteTokens.space2),
                const Text(
                  'Scraps and images stay as readable files on this computer.',
                  style: TextStyle(
                    color: ScrapnoteTokens.charcoalSoft,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: ScrapnoteTokens.space5),
                FButton(
                  key: const ValueKey<String>('onboarding-choose-folder'),
                  onPress: loading ? null : onChooseVault,
                  prefix: loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: ScrapnoteTokens.paperRaised,
                          ),
                        )
                      : const Icon(FLucideIcons.folderOpen, size: 16),
                  child: Text(loading ? 'Opening…' : 'Choose folder'),
                ),
                const SizedBox(height: ScrapnoteTokens.space5),
                const Divider(height: 1, color: ScrapnoteTokens.rule),
                const SizedBox(height: ScrapnoteTokens.space4),
                const Row(
                  children: <Widget>[
                    Text(
                      '2 / 2',
                      style: TextStyle(
                        color: ScrapnoteTokens.ruleStrong,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: ScrapnoteTokens.space3),
                    Expanded(
                      child: Text(
                        'Start writing',
                        style: TextStyle(
                          color: ScrapnoteTokens.mutedInk,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

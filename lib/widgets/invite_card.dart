import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_analytics.dart';
import '../services/referral_service.dart';
import 'cine_ui.dart';

/// v1.0.1+58: "INVITE & EARN" card — progress to the 6-month ad-free
/// reward, one-tap share, copy-code, claim friend code. Collapses into a
/// thank-you chip while ad-free is active.
class InviteCard extends StatelessWidget {
  const InviteCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = ReferralService.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: ReferralService.adsFree,
      builder: (context, free, _) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: kCineAmber.withValues(alpha: 0.6),
                width: 1.2,
              ),
              gradient: LinearGradient(
                colors: [
                  kCineAmber.withValues(alpha: 0.14),
                  kCinePink.withValues(alpha: 0.08),
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [kCineAmber, kCinePink]),
                  ),
                  child: Icon(
                    free
                        ? Icons.workspace_premium_rounded
                        : Icons.card_giftcard_rounded,
                    color: Colors.black,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        free
                            ? 'AD-FREE UNTIL ${ref.adFreeUntilLabel}'
                            : 'INVITE & EARN',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        free
                            ? 'Enjoying it? Keep the streak going'
                            : '3 friends = 6 months ad-free • tap to share',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!free) ...[
                  Text(
                    '${ref.referralCount % ReferralService.kReferralsPerReward}/${ReferralService.kReferralsPerReward}',
                    style: const TextStyle(
                      color: kCineCyan,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                const Icon(Icons.chevron_right, color: kCineCyan, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    AppAnalytics.instance.log('invite_opened');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12121a),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _InviteSheet(),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet();

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _codeCtrl = TextEditingController();
  bool _claiming = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = ReferralService.instance;
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'INVITE & EARN',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Share your code. Every ${ReferralService.kReferralsPerReward} '
            'friends who install & claim it unlock '
            '${ReferralService.kRewardDays} days with NO ADS — stacked.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: kCinePurple.withValues(alpha: 0.18),
              border: Border.all(color: kCinePurple, width: 1.3),
            ),
            child: Text(
              ref.code ?? '…',
              textAlign: TextAlign.center,
              style: cineMono(24, Colors.white, letterSpacing: 5),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: ref.code ?? ''));
                    AppAnalytics.instance.log('referral_code_copied');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('COPY'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kCinePink,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    AppAnalytics.instance.log('referral_shared');
                    AppAnalytics.instance.bumpDaily(shares: 1);
                    SharePlus.instance.share(ShareParams(text: ref.shareText));
                  },
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('SHARE THE APP'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Have a friend\u2019s code?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'MAX-XXXX',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kCineCyan,
                  foregroundColor: Colors.black,
                ),
                onPressed: _claiming ? null : _claim,
                child: _claiming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('CLAIM'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _claim() async {
    setState(() => _claiming = true);
    final entered = _codeCtrl.text;
    final msg = await ReferralService.instance.claimCode(entered);
    if (!mounted) return;
    setState(() => _claiming = false);
    if (msg == null) {
      await ReferralService.instance.markClaimed(entered.trim().toUpperCase());
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code claimed — welcome in!')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'kit.dart';
import 'scale.dart';

/// "Update ready": the new version is downloaded. Restart now, or let it
/// install the next time the app is closed. True if the user chose restart.
Future<bool> showUpdateReady(BuildContext context) async {
  final restart = await showAppSheet<bool>(
    context,
    builder: (ctx) {
      final p = Pal.of(ctx);
      return Padding(
        padding: EdgeInsets.fromLTRB(20.dp, 12.dp, 20.dp, 16.dp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Update ready',
              style: TextStyle(
                color: p.ink,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6.dp),
            Text(
              'The new version of Dates is downloaded. Restart to finish, '
              'or it installs the next time you close the app.',
              style: TextStyle(color: p.sub, fontSize: 14.sp, height: 1.35),
            ),
            SizedBox(height: 16.dp),
            GlassPress(
              label: 'Restart',
              onTap: () => Navigator.of(ctx).pop(true),
              builder: (down) => SizedBox(
                height: 46.dp,
                child: GlassSurface(
                  radius: 23.dp,
                  lit: down,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(
                        p.accentRaw,
                        Colors.white,
                        0.12,
                      )!.withValues(alpha: 0.96),
                      Color.lerp(
                        p.accentRaw,
                        Colors.black,
                        0.10,
                      )!.withValues(alpha: 0.96),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'Restart',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 6.dp),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Later',
                style: TextStyle(color: p.sub, fontSize: 15.sp),
              ),
            ),
          ],
        ),
      );
    },
  );
  return restart ?? false;
}

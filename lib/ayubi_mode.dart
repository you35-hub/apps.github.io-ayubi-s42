import 'package:flutter/material.dart';
import 'orb_3d.dart';

class AyubiMode extends StatelessWidget {
  final OrbState state;
  final String brainName;
  final String brainEmoji;

  const AyubiMode({
    super.key,
    this.state = OrbState.idle,
    this.brainName = 'Ayubi',
    this.brainEmoji = '🧠',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Orb3D(state: state, size: 320),
    );
  }
}
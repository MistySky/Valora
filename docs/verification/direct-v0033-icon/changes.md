# Codex direct icon correction

- Preserve Status Trio single-circle center/radius, restore its 35.3/29.4/35.3 top gap rather than drawing through the date.
- CPU fills the left visible arc from the bottom; memory fills the right visible arc from the bottom.
- AppKit bitmap contexts already apply their pixels/points scale (verified CTM=2 for 44px/22pt); do not multiply it again.
- Date moved into the upper gap; arrow shaft extends from source y40 to79, with separate baseline and quota dots.
- Four whole quota dots: per 50-percent bucket, full green, partial yellow, empty/unknown gray. No circle clipping.
- Codex content accepts its actual container width; embedded card uses 368pt rather than overflowing a 368pt card with a 400pt child.
- Calendar source/layout unchanged. No popup automation/performance tests. User runtime left unchanged.

Latest targeted build/test results are recorded in /private/tmp/valora-direct-icon-tests.log and /private/tmp/valora-direct-single-ring-build.log; candidate is not claimed to have passed live visual acceptance.

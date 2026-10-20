# sigil_crypto on sky130hd — deltas from the nangate45 flow

The canonical closed result is nangate45 (#3); this config is the
starting point for the same macro on sky130hd (full-SoC closure
is #11). No sky130hd run is claimed yet. Deltas already applied
here relative to `../../nangate45/sigil_crypto/`:

| Parameter | nangate45 | sky130hd | Why |
|---|---|---|---|
| `CLOCK_PERIOD` | 10 ns (100 MHz) | 20 ns (50 MHz) | Conservative first target on the slower node |
| `CORE_UTILIZATION` | 28 | 35 | Re-tune after first run |
| `PLACE_DENSITY_LB_ADDON` | 0.05 | 0.10 | More placement headroom for routability |
| SDC uncertainty (setup/hold) | 0.5 / 0.05 ns | 1.0 / 0.1 ns | Scaled with period; keep split (combined uncertainty broke CTS hold on nangate45) |
| SDC I/O delays | 2.0 ns | 4.0 ns | Scaled placeholder budget |
| `EARLY_SIZING_CAP_RATIO` | 0.8 | (add on first run) | Same post-route max-cap guardband; sky130 liberty caps differ, re-measure violation count first |

Still to determine on the first sky130hd run: achievable clock
(the macro has large setup margin at 100 MHz on nangate45, so
50 MHz should be comfortable), whether the 35% utilization
routes cleanly, and the max-cap guardband needed. Run with
`PLATFORM=sky130hd ./scripts/openroad_docker.sh`.

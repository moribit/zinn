# Prespecified validation comparisons

Official train split: deterministic shuffle with split_seed=24301, 55,000 updates-only / 5,000 validation. Training seed comparisons do not alter this partition. Official test is not opened during these runs. Mini-batch=32, SGD, CE; rate decay every10 epochs by0.3; calibration from training partition only.

Fixed comparisons: MLP16/rate.05/10 epochs; MLP16/.05/30; MLP32/.05/20; MLP32/.1/20; MLP32/.05/20 nearest preprocessing versus area. CNN2/.05/20 versus CNN4/.05/20. Area is otherwise fixed. Seed42 is the controlled comparison. Repeat selected MLP configuration with seed43 as a separate reproducibility observation, not a broad statistical claim.

Choose the deployment candidate using validation accuracy (ties: CE), memory budget and simplicity. After freezing the configuration, run official test once per selected candidate/format; never feed official test to training, calibration or selection. Best epoch is selected from validation curve. Existing checkpoint v1 is maintained and a sidecar curve/config is required to interpret preprocessing and validation provenance.

## Frozen final evaluation (2026-11-07)

Before reading official test: select MLP32, rate0.1, 20 epochs, seed42, area preprocessing (best validation epoch13); CNN4, rate0.05, 20 epochs, seed42, area (best epoch19). Both use calibration1024 from the training partition, int8 and int4. Retain seed43 as a separate repeat, not the primary selection. Calibration256 slightly improves validation accuracy but increases maximum logit error; 4096 gives no int8 accuracy improvement. Keep1024 for both formats.

Validation production builds: MLP32 int8 Flash12408B/static RAM460B; CNN4 int8 Flash6436B/static RAM1408B. With512B stack allowance, CNN4 has only128B RAM margin: accepted for this bounded transport example, not a general application headroom guarantee. Its normal-path static stack estimate is224B, excluding interrupts; hardware remains unverified.

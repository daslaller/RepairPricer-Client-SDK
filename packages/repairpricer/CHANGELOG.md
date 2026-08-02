## 0.1.0

- First public release. Extracted from the closed RepairPricer monorepo as a
  standalone package so subscribers can depend on it without access to the
  commercial product.
- Now depends on `repairpricer_contract` instead of the private
  `repairpricer_core`. The re-exported surface loses the platform-only
  service-fee calculator (`ServiceFeeCalculator`, `resolveServiceFeeForSync`);
  `VerificationStatus` / `VerificationLevel` are unchanged and still exported.

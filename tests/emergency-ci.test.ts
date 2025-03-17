import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("emergency-ci contract", () => {
    it("allows users to contribute to the pool", () => {
        const contributeCall = simnet.callPublicFn("emergency-ci", "contribute", [], wallet1);
        expect(contributeCall.result).toBeOk(Cl.bool(true));
        
        const balanceCall = simnet.callReadOnlyFn(
            "emergency-ci",
            "get-contribution",
            [Cl.principal(wallet1)],
            wallet1
        );
        expect(balanceCall.result).toBeUint(1000000);
    });

    it("allows contract owner to create claims", () => {
      // First contribute to the pool
      simnet.callPublicFn("emergency-ci", "contribute", [], wallet1);
      
      const createClaimCall = simnet.callPublicFn(
          "emergency-ci",
          "create-claim",
          [Cl.uint(500000)],
          deployer
      );
      expect(createClaimCall.result).toBeOk(Cl.bool(true));
  });



    it("tracks total pool balance", () => {
        const balanceCall = simnet.callReadOnlyFn(
            "emergency-ci",
            "get-pool-balance",
            [],
            deployer
        );
        expect(balanceCall.result).toBeUint(0);
    });
});

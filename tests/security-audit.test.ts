import { describe, it, beforeEach, expect } from 'vitest';
import { Cl } from '@stacks/transactions';

const accounts = simnet.getAccounts();
const deployer = accounts.get('deployer')!;
const auditor1 = accounts.get('wallet_1')!;
const auditor2 = accounts.get('wallet_2')!;
const auditor3 = accounts.get('wallet_3')!;

describe('Security Audit System', () => {
  beforeEach(() => {
    simnet.deployContract('security-audit', './contracts/security-audit.clar', null, deployer);
  });

  describe('Auditor Management', () => {
    it('should certify new auditors', () => {
      const result = simnet.callPublicFn(
        'security-audit',
        'certify-auditor',
        [Cl.principal(auditor1), Cl.uint(1000)],
        deployer
      );
      expect(result.result).toBeOk(Cl.bool(true));
    });

    it('should prevent non-owners from certifying auditors', () => {
      const result = simnet.callPublicFn(
        'security-audit',
        'certify-auditor',
        [Cl.principal(auditor2), Cl.uint(1000)],
        auditor1
      );
      expect(result.result).toBeErr(Cl.uint(800));
    });

    it('should retrieve auditor profiles', () => {
      simnet.callPublicFn(
        'security-audit',
        'certify-auditor',
        [Cl.principal(auditor1), Cl.uint(1000)],
        deployer
      );

      const profile = simnet.callReadOnlyFn(
        'security-audit',
        'get-auditor-profile',
        [Cl.principal(auditor1)],
        deployer
      );
      
      expect(profile.result).toBeSome(
        Cl.tuple({
          reputation: Cl.uint(1000),
          'total-audits': Cl.uint(0),
          'successful-audits': Cl.uint(0),
          'certification-date': Cl.uint(simnet.blockHeight - 1)
        })
      );
    });
  });

  describe('Audit Submission', () => {
    beforeEach(() => {
      simnet.callPublicFn(
        'security-audit',
        'certify-auditor',
        [Cl.principal(auditor1), Cl.uint(1000)],
        deployer
      );
    });

    it('should allow certified auditors to submit audits', () => {
      const result = simnet.callPublicFn(
        'security-audit',
        'submit-audit',
        [
          Cl.stringAscii('emergency-ci'),
          Cl.stringAscii('No critical vulnerabilities found'),
          Cl.uint(15),
          Cl.uint(8)
        ],
        auditor1
      );
      expect(result.result).toBeOk(Cl.uint(0));
    });

    it('should reject audits from uncertified auditors', () => {
      const result = simnet.callPublicFn(
        'security-audit',
        'submit-audit',
        [
          Cl.stringAscii('emergency-ci'),
          Cl.stringAscii('Security review complete'),
          Cl.uint(20),
          Cl.uint(7)
        ],
        auditor2
      );
      expect(result.result).toBeErr(Cl.uint(800));
    });

    it('should reject invalid ratings', () => {
      const result = simnet.callPublicFn(
        'security-audit',
        'submit-audit',
        [
          Cl.stringAscii('emergency-ci'),
          Cl.stringAscii('Security review'),
          Cl.uint(20),
          Cl.uint(15)
        ],
        auditor1
      );
      expect(result.result).toBeErr(Cl.uint(803));
    });
  });

  describe('Audit Voting', () => {
    beforeEach(() => {
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor1), Cl.uint(1000)], deployer);
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor2), Cl.uint(800)], deployer);
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor3), Cl.uint(600)], deployer);
      
      simnet.callPublicFn(
        'security-audit',
        'submit-audit',
        [Cl.stringAscii('emergency-ci'), Cl.stringAscii('Initial findings'), Cl.uint(25), Cl.uint(7)],
        auditor1
      );
    });

    it('should allow certified auditors to vote', () => {
      const result = simnet.callPublicFn(
        'security-audit',
        'vote-on-audit',
        [Cl.uint(0), Cl.uint(8), Cl.uint(85)],
        auditor2
      );
      expect(result.result).toBeOk(Cl.bool(true));
    });

    it('should prevent duplicate voting', () => {
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(0), Cl.uint(8), Cl.uint(85)], auditor2);
      
      const duplicateVote = simnet.callPublicFn(
        'security-audit',
        'vote-on-audit',
        [Cl.uint(0), Cl.uint(9), Cl.uint(90)],
        auditor2
      );
      expect(duplicateVote.result).toBeErr(Cl.uint(802));
    });

    it('should reject votes from low reputation auditors', () => {
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(accounts.get('wallet_4')!), Cl.uint(300)], deployer);
      
      const result = simnet.callPublicFn(
        'security-audit',
        'vote-on-audit',
        [Cl.uint(0), Cl.uint(8), Cl.uint(85)],
        accounts.get('wallet_4')!
      );
      expect(result.result).toBeErr(Cl.uint(804));
    });
  });

  describe('Audit Completion', () => {
    beforeEach(() => {
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor1), Cl.uint(1000)], deployer);
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor2), Cl.uint(800)], deployer);
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor3), Cl.uint(600)], deployer);
      
      simnet.callPublicFn(
        'security-audit',
        'submit-audit',
        [Cl.stringAscii('emergency-ci'), Cl.stringAscii('Comprehensive audit'), Cl.uint(30), Cl.uint(8)],
        auditor1
      );
    });

    it('should complete audit after minimum votes', () => {
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(0), Cl.uint(7), Cl.uint(80)], auditor2);
      
      const finalVote = simnet.callPublicFn(
        'security-audit',
        'vote-on-audit',
        [Cl.uint(0), Cl.uint(9), Cl.uint(95)],
        auditor3
      );
      expect(finalVote.result).toBeOk(Cl.bool(true));
      
      const auditDetails = simnet.callReadOnlyFn(
        'security-audit',
        'get-audit-details',
        [Cl.uint(0)],
        deployer
      );
      
      const audit = auditDetails.result.expectSome().expectTuple();
      expect(audit.status).toBeUint(2);
    });

    it('should update contract ratings after completion', () => {
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(0), Cl.uint(8), Cl.uint(85)], auditor2);
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(0), Cl.uint(7), Cl.uint(80)], auditor3);
      
      const rating = simnet.callReadOnlyFn(
        'security-audit',
        'get-contract-security-rating',
        [Cl.stringAscii('emergency-ci')],
        deployer
      );
      
      expect(rating.result).toBeSome();
    });
  });

  describe('Security Ratings', () => {
    beforeEach(() => {
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor1), Cl.uint(1000)], deployer);
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor2), Cl.uint(800)], deployer);
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor3), Cl.uint(600)], deployer);
    });

    it('should calculate trust scores correctly', () => {
      simnet.callPublicFn('security-audit', 'submit-audit', [Cl.stringAscii('test-contract'), Cl.stringAscii('Low risk audit'), Cl.uint(10), Cl.uint(9)], auditor1);
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(0), Cl.uint(9), Cl.uint(90)], auditor2);
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(0), Cl.uint(8), Cl.uint(85)], auditor3);
      
      const trustScore = simnet.callReadOnlyFn(
        'security-audit',
        'calculate-trust-score',
        [Cl.stringAscii('test-contract')],
        deployer
      );
      
      expect(trustScore.result).toBeUint(99);
    });

    it('should handle multiple audits for same contract', () => {
      simnet.callPublicFn('security-audit', 'submit-audit', [Cl.stringAscii('multi-audit'), Cl.stringAscii('First audit'), Cl.uint(20), Cl.uint(8)], auditor1);
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(0), Cl.uint(8), Cl.uint(85)], auditor2);
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(0), Cl.uint(7), Cl.uint(80)], auditor3);
      
      simnet.callPublicFn('security-audit', 'submit-audit', [Cl.stringAscii('multi-audit'), Cl.stringAscii('Second audit'), Cl.uint(15), Cl.uint(9)], auditor2);
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(1), Cl.uint(9), Cl.uint(90)], auditor1);
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(1), Cl.uint(8), Cl.uint(85)], auditor3);
      
      const rating = simnet.callReadOnlyFn(
        'security-audit',
        'get-contract-security-rating',
        [Cl.stringAscii('multi-audit')],
        deployer
      );
      
      const ratingData = rating.result.expectSome().expectTuple();
      expect(ratingData['total-audits']).toBeUint(2);
    });
  });

  describe('Audit Disputes', () => {
    beforeEach(() => {
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor1), Cl.uint(1000)], deployer);
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor2), Cl.uint(1200)], deployer);
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor3), Cl.uint(600)], deployer);
      
      simnet.callPublicFn('security-audit', 'submit-audit', [Cl.stringAscii('disputed-contract'), Cl.stringAscii('Questionable findings'), Cl.uint(40), Cl.uint(5)], auditor1);
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(0), Cl.uint(6), Cl.uint(70)], auditor2);
      simnet.callPublicFn('security-audit', 'vote-on-audit', [Cl.uint(0), Cl.uint(4), Cl.uint(60)], auditor3);
    });

    it('should allow high reputation auditors to dispute', () => {
      const result = simnet.callPublicFn(
        'security-audit',
        'dispute-audit',
        [Cl.uint(0), Cl.stringAscii('Findings appear inaccurate')],
        auditor2
      );
      expect(result.result).toBeOk(Cl.bool(true));
      
      const auditDetails = simnet.callReadOnlyFn(
        'security-audit',
        'get-audit-details',
        [Cl.uint(0)],
        deployer
      );
      
      const audit = auditDetails.result.expectSome().expectTuple();
      expect(audit.status).toBeUint(3);
    });

    it('should prevent low reputation auditors from disputing', () => {
      const result = simnet.callPublicFn(
        'security-audit',
        'dispute-audit',
        [Cl.uint(0), Cl.stringAscii('I disagree with findings')],
        auditor3
      );
      expect(result.result).toBeErr(Cl.uint(804));
    });
  });

  describe('Read-Only Functions', () => {
    beforeEach(() => {
      simnet.callPublicFn('security-audit', 'certify-auditor', [Cl.principal(auditor1), Cl.uint(1000)], deployer);
    });

    it('should check auditor certification status', () => {
      const certified = simnet.callReadOnlyFn(
        'security-audit',
        'is-certified-auditor',
        [Cl.principal(auditor1)],
        deployer
      );
      expect(certified.result).toBeBool(true);
      
      const notCertified = simnet.callReadOnlyFn(
        'security-audit',
        'is-certified-auditor',
        [Cl.principal(auditor2)],
        deployer
      );
      expect(notCertified.result).toBeBool(false);
    });

    it('should return total audit count', () => {
      const totalBefore = simnet.callReadOnlyFn('security-audit', 'get-total-audits', [], deployer);
      expect(totalBefore.result).toBeUint(0);
      
      simnet.callPublicFn('security-audit', 'submit-audit', [Cl.stringAscii('test'), Cl.stringAscii('test'), Cl.uint(10), Cl.uint(8)], auditor1);
      
      const totalAfter = simnet.callReadOnlyFn('security-audit', 'get-total-audits', [], deployer);
      expect(totalAfter.result).toBeUint(1);
    });
  });
});

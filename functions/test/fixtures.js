// Synthetic alerts modelled on common Nigerian bank formats. Not real accounts.
export const fixtures = [
  {
    name: 'GTBank POS fuel',
    raw: `GTBank Alert
Acct: 0123****89
Amt: NGN15,000.00 DR
Desc: POS/WEB PURCHASE TOTAL ENERGIES UYO
Avail Bal: NGN45,210.33
Date: 2026-09-05 14:22`,
    expect: { direction: 'debit', amountKobo: 1500000, date: '2026-09-05', bank: 'gtbank', balanceKobo: 4521033 },
  },
  {
    name: 'Access transfer to Emeka',
    raw: `Debit
Amt:NGN2,500.00
Acc:123**890
Desc:TRF TO EMEKA OKAFOR/ACCESS MOBILE
Date:12/09/2026
Avail Bal:NGN30,100.00`,
    sender: 'AccessBank',
    expect: { direction: 'debit', amountKobo: 250000, date: '2026-09-12', bank: 'access', counterparty: 'EMEKA OKAFOR' },
  },
  {
    name: 'Zenith NIP',
    raw: `Acct:21**23
DT:18/09/2026:14:30
NIP/MONIEPOINT/EMEKA OKAFOR
DR Amt:5,000.00
Bal:22,000.00`,
    sender: 'ZENITHBANK',
    expect: { direction: 'debit', amountKobo: 500000, date: '2026-09-18', bank: 'zenith', counterparty: 'EMEKA OKAFOR' },
  },
  {
    name: 'First Bank airtime',
    raw: 'Debit: 012XXXX89: NGN1,500.00 on 05-OCT-2026 12:03 by AIRTIME MTN 0803. Bal: NGN18,450.00',
    sender: 'FirstBank',
    expect: { direction: 'debit', amountKobo: 150000, date: '2026-10-05', bank: 'firstbank' },
  },
  {
    name: 'OPay credit',
    raw: 'OPay: You have received ₦120,000.00 from SHIPPOR LABS LTD. Balance: ₦140,500.00',
    expect: { direction: 'credit', amountKobo: 12000000, bank: 'opay', counterparty: 'SHIPPOR LABS LTD' },
  },
  {
    name: 'UBA salary credit',
    raw: `Txn: Credit
Ac:20XXXXXX12
Amt:NGN 250,000.00
Des:SALARY OCT 2026 FHENIX AFRICA
Date:25-Oct-2026 09:10
Bal:NGN 260,400.00`,
    sender: 'UBA',
    expect: { direction: 'credit', amountKobo: 25000000, date: '2026-10-25', bank: 'uba' },
  },
  {
    name: 'Moniepoint transfer out',
    raw: 'Moniepoint: Transfer of ₦3,000 to CHIOMA NWOSU successful on 20/10/2026.',
    expect: { direction: 'debit', amountKobo: 300000, date: '2026-10-20', bank: 'moniepoint', counterparty: 'CHIOMA NWOSU' },
  },
  {
    name: 'not an alert',
    raw: 'Your OTP is 123456. Do not share.',
    expectFail: true,
  },
];

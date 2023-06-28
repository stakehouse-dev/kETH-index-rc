# DETH Vault (kwETH)

DETH vault is a vault contract where dETH holders can lock their funds for ETH back.

## Mint kwETH

  dETH holders can deposit dETH and get share of the vault.

## Swap ETH for dETH

  ETH holders can deposit ETH and get dETH back with 1:1 rate.

## Burn kwETH

  Vault holders can burn their kwETH and get ETH/dETH back.
  They can choose ETH or dETH for withdrawal asset.

** The dETH in the vault contract are invested into savETH registry and continue yield generation.

## Manage dETH/savETH

  The vault owner can manage dETH/savETH via SavETHRegistry contract.
  He can isolate knot or rotate knot to generate more yield from invested dETH.

# KETH Vault (kETH)

KETH is more like the index token for wstETH, rETH and dETH.

## Workflow

![kETH mint/burn workflow](/workflow.png "kETH mint/burn workflow")

## Mint kETH

  wstETH, rETH and dETH holders can join and mint kETH based on their deposit value in ETH.

  kETH Mint Formula
  ```
  V = users deposit amount in ETH
  Ta = total assets value in ETH
  Tk = kETH total supply
  kETH amount to mint = V * Tk / Ta
  ```

## Burn kETH

  kETH holder can burn their LP and get their portion of the vault in ETH and dETH.
  
  kETH Burn Formula
  ```
  X = kETH burn amount
  Tk = kETH total supply
  dETH amount back = total dETH amount * X / Tk
  wstETH amount for sell = total wstETH amount * X / Tk
  rETH amount for sell = total rETH amount * X / Tk
  ```

  Here the point is that we swap all wstETH and rETH for ETH and transfer ETH back to the user.
  As a result the user gets ETH and dETH. If he wants to swap dETH for ETH, he can use above dETH vault.

## Index management

- Deposit Ceiling
  
  Strategy manager can set deposit-ceiling per each asset.
  This will allow strategy manager to control funds deposits from users.

  E.g.
  If he wants to decrease index of wstETH, he will decrease the deposit ceiling of wstETH.
  And then unwrap wstETH for stETH, swap stETH for ETH using curve, swap ETH for dETH using dETH vault.

- Swap wstETH, rETH for dETH
  
  Strategy manager can trigger the swap action for index management.

  ALl the swap action will be done via `swapper` smart contract.
  The swapper smart contract behaves similar to UniswapV2Router. It receives exact amount of input token, swapt it for output token, and then transfer output token back to the user.

  The strategy owner can set the verified swappers and the strategy manager can use one of the verified swapper for index management.

  Here are some swappers we use for wstETH and rETH;
  RETHToDETH: swap rETH for dETH
  RETHToETH: swap rETH for ETH
  WstETHToDETH: swap wstETH for dETH
  WstETHToETH: swap wstETH for ETH

## Manage dETH/savETH

  The strategy manager can manage dETH/savETH via SavETHRegistry contract.
  He can isolate knot or rotate knot to generate more yield from invested dETH.

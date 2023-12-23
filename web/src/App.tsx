import { useState } from 'react'
import reactLogo from './assets/react.svg'
import viteLogo from '/vite.svg'
import './App.css'
import { keccak256_gpu_batch } from 'keccak256-webgpu';

/** SDK */
import {
  Ed25519Keypair,
  PrivateKeyAuth,
  IAccount,
  Account,
  encodeMoveCallDataWithETH,
} from '@roochnetwork/rooch-sdk'

function App() {
  const handleMint = () => {
    const moveCallData = encodeMoveCallDataWithETH('default::movescription::mint_mrc20', [], [])

    const params = [
      {
        from: eth.activeAccount!.address,
        to: ROOCH_ADDRESS,
        gas: '0x76c0', // 30400
        gasPrice: '0x9184e72a000', // 10000000000000
        value: '0x4e72a', // 2441406250
        data: moveCallData,
      },
    ]

    try {
      await ethereum.request({
        method: 'eth_sendTransaction',
        params,
      })
    } catch (e: any) {
      console.log(e)
    } finally {
      setLoading(false)
    }
  }

  return (
    <>
      <div className="card">
        <button onClick={() => handleMint()}>
          Mint
        </button>
      </div>
    </>
  )
}

export default App

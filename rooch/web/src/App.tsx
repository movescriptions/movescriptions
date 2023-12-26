import { useState } from 'react'
import './App.css'

/** SDK */
import {
  RoochClient, DevChain, Account, Ed25519Keypair, PrivateKeyAuth,
  IAccount,
} from '@roochnetwork/rooch-sdk'

import { MinerManager, IMinerTask } from './miner'

const moveScriptionAddress = `${import.meta.env.VITE_MOVE_SCRIPTIONS_ADDRESS}`
const mrc20PowInputFunc = `${moveScriptionAddress}::movescription::pow_input`
const mrc20MintFunc = `${moveScriptionAddress}::mrc20::do_mint`

const client = new RoochClient(DevChain)
const kp = Ed25519Keypair.deriveKeypair(
  'nose aspect organ harbor move prepare raven manage lamp consider oil front',
)
const roochAddress = kp.getPublicKey().toRoochAddress()
const authorizer = new PrivateKeyAuth(kp)
const account = new Account(client, roochAddress, authorizer)
const minerManager = new MinerManager(1, 0);

function App() {
  const [minting, setMinting] = useState(false);

  const getPowInput = async (account: IAccount, tick: string, value: number) => {
    const resp = await client.executeViewFunction(
      mrc20PowInputFunc,
      [],
      [
        {
          type: 'Address',
          value: account.getAddress(),
        },
        {
          type: 'String',
          value: tick,
        },
        {
          type: 'U256',
          value: value,
        }
      ],
    )

    if (resp.vm_status == 'Executed') {
      return resp.return_values?.[0]?.value?.value;
    }

    throw new Error("get_pow_input_error:" + JSON.stringify(resp))
  }

  const searchNonce = async (account: IAccount, tick: string, value: number, difficulty: number) => {
    const powInput = await getPowInput(account, tick, value)

    if (powInput) {
      const task: IMinerTask = {
        id: "1",
        powData: powInput,
        difficulty: difficulty,
        nonceStart: 1,
        nonceEnd: 10000,
        timestamp: new Date().getTime(),
        onSuccess: ()=>{
  
        },
        onError: ()=>{
          
        }
      }
  
      minerManager.addTask(task);
    }
  
    return 0
  }

  const handleMint = async (account: IAccount) => {
    setMinting(true)

    const nonce = await searchNonce(account, "move", 1000, 2)
    console.log("found nonce:", nonce);

    try {
      const tx = await account.runFunction(mrc20MintFunc, [], [], {
        maxGasAmount: 100000000,
      })

      console.log('tx:', tx)
    } catch (e: unknown) {
      console.log(e)
    } finally {
      setMinting(false)
    }
  }

  return (
    <>
      <div className="card">
        {minting && (
          <div>
            Minting...
          </div>
        )}

        <button onClick={() => handleMint(account)}>
          Mint
        </button>
      </div>
    </>
  )
}

export default App

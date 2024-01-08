import { useState } from 'react'
import './App.css'

/** SDK */
import {
  RoochClient, DevChain, Account, Ed25519Keypair, PrivateKeyAuth,
  IAccount,
} from '@roochnetwork/rooch-sdk'

import { MinerManager, IMinerTask, IMintResult, ProgressPayload } from './miner'

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
  const [progress, setProgress] = useState("");

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
      return new Promise((resolve, reject) => {
        const task: IMinerTask = {
          id: "1",
          powData: powInput,
          difficulty: difficulty,
          timestamp: new Date().getTime(),
          onEnd: (result: IMintResult)=>{
            minerManager.stop()
            resolve(result);
          },
          onError: (err: Error)=>{
            minerManager.stop()
            reject(err)
          },
          onProgress: (payload: ProgressPayload)=>{
            setProgress(payload.progress)
          }
        }
    
        minerManager.addTask(task);
        minerManager.start();
      });      
    }
  
    throw new Error('pow input invalid')
  }

  const handleMint = async (account: IAccount) => {
    setMinting(true)

    try {
      const nonce = await searchNonce(account, "move", 1000, 9)
      console.log("found nonce:", nonce);

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

  const handleStop = async () => {
    setMinting(false)
    minerManager.stop();
    console.log("stop mint success!");
  }

  return (
    <>
      <div className="card">
        {!minting && (
          <button onClick={() => handleMint(account)}>
            Mint
          </button>
        )}

        {minting && (
          <div>
            <div>
              Minting...
            </div>
            <div>
              {progress}
            </div>
            <button onClick={() => handleStop()}>
              Stop
            </button>
          </div>
        )}

      </div>
    </>
  )
}

export default App

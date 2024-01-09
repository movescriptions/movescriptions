import { useState } from 'react'
import './App.css'

/** SDK */
import {
  RoochClient, DevChain, Account, Ed25519Keypair, PrivateKeyAuth,
  IAccount,
} from '@roochnetwork/rooch-sdk'

import { MinerManager, IMinerTask, IMintResult } from './miner'

const moveScriptionAddress = `${import.meta.env.VITE_MOVE_SCRIPTIONS_ADDRESS}`
const mrc20PowInputFunc = `${moveScriptionAddress}::movescription::pow_input`
const mrc20PowValidateFunc = `${moveScriptionAddress}::movescription::validate_pow`
const mrc20MintFunc = `${moveScriptionAddress}::mrc20::do_mint`

const client = new RoochClient(DevChain)
const kp = Ed25519Keypair.deriveKeypair(
  'nose aspect organ harbor move prepare raven manage lamp consider oil front',
)
const roochAddress = kp.getPublicKey().toRoochAddress()
const authorizer = new PrivateKeyAuth(kp)
const account = new Account(client, roochAddress, authorizer)
let minerManager = new MinerManager(4, 0);

function App() {
  const [minting, setMinting] = useState(false);
  const [progress, setProgress] = useState("");
  const [mintResult, setMintResult] = useState<IMintResult|undefined>(undefined);
  const [errorMsg, setErrorMsg] = useState<string|undefined>(undefined);

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

  const validatePow = async (account: IAccount, tick: string, value: number, difficulty: number, nonce: number) => {
    const resp = await client.executeViewFunction(
      mrc20PowValidateFunc,
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
        },
        {
          type: 'U64',
          value: difficulty,
        },
        {
          type: 'U64',
          value: nonce,
        }
      ],
    )

    if (resp.vm_status == 'Executed') {
      return resp.return_values?.[0]?.decoded_value;
    }

    throw new Error("validate_pow_error:" + JSON.stringify(resp))
  }

  const searchNonce = async (account: IAccount, tick: string, value: number, difficulty: number): Promise<IMintResult> => {
    const powInput = await getPowInput(account, tick, value)

    if (powInput) {
      minerManager = new MinerManager(8, 0);

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
          onProgress: (progress: string)=>{
            setProgress(progress)
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

    const tick = 'move';
    const difficulty = 2;

    try {
      const result = await searchNonce(account, tick, 1000, difficulty)
      console.log("found nonce:", result.nonce, 'hash:', result.hash);

      if (!await validatePow(account, tick, 1000, difficulty, result.nonce)) {
        setErrorMsg(`found nonce: ${result.nonce}, hash: ${result.hash} invalid!`)
        return
      }

      setMintResult(result)

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
          <div>
            {mintResult && (
              <div>Found nonce: {mintResult.nonce}, hash: {mintResult.hash}</div>
            )}

            {errorMsg && (
              <div style={{color: 'red'}}>Error: {errorMsg}</div>
            )}

            <button onClick={() => handleMint(account)}>
              Mint
            </button>
          </div>
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

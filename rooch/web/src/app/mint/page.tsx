'use client';
import { useState } from 'react'
import Container from '@mui/material/Container';
import Button from '@mui/material/Button';

import { arrayify } from "@ethersproject/bytes"
import { MinerManager, IMinerTask, IMintResult, IMintProgress } from '../../miner'
import { humanReadableHashrate } from '../../utils/hashRate'

import { movescriptionConfig } from '@/config/movescription'

/** SDK */
import {
  RoochClient, DevChain, Account, Ed25519Keypair, PrivateKeyAuth,
  IAccount,
} from '@roochnetwork/rooch-sdk'

const moveScriptionAddress = `${movescriptionConfig.movescriptionAddress}`
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

export default function Mint() {
  const [minting, setMinting] = useState(false);
  const [progress, setProgress] = useState<IMintProgress|undefined>(undefined);
  const [mintResult, setMintResult] = useState<IMintResult|undefined>(undefined);
  const [errorMsg, setErrorMsg] = useState<string|undefined>(undefined);
  const [tx, setTX] = useState<string|undefined>(undefined);

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

    console.log("getPowInput resp:", resp);

    if (resp.vm_status == 'Executed') {
      return resp.return_values?.[0]?.decoded_value as string;
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

    console.log("validatePow resp:", resp);

    if (resp.vm_status == 'Executed') {
      return resp.return_values?.[0]?.decoded_value;
    }

    throw new Error("validate_pow_error:" + JSON.stringify(resp))
  }

  const searchNonce = async (account: IAccount, tick: string, value: number, difficulty: number): Promise<IMintResult> => {
    const powInput = await getPowInput(account, tick, value)

    if (powInput) {
      minerManager = new MinerManager(6, 1);

      return new Promise((resolve, reject) => {
        const task: IMinerTask = {
          id: "1",
          powData: arrayify(powInput),
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
          onProgress: (progress: IMintProgress)=>{
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
    const amount = 1000;
    const difficulty = 3;

    try {
      const result = await searchNonce(account, tick, amount, difficulty)
      console.log("found nonce:", result.nonce, 'hash:', result.hash);

      if (!await validatePow(account, tick, amount, difficulty, result.nonce)) {
        setErrorMsg(`found nonce: ${result.nonce}, hash: ${result.hash} invalid!`)
        return
      }

      setMintResult(result)

      const tx = await account.runFunction(mrc20MintFunc, [], [
        {
          type: 'Object',
          value: {
            address: moveScriptionAddress,
            module: 'mrc20',
            name: 'MRC20Store',
          },
        },
        {
          type: 'String',
          value: tick,
        },
        {
          type: 'U64',
          value: result.nonce,
        },
        {
          type: 'U256',
          value: amount,
        },
      ], {
        maxGasAmount: 100000000,
      })

      console.log('mint tx:', tx)
      setProgress(undefined)
      setTX(tx)
    } catch (e: unknown) {
      console.log(e)
    } finally {
      setMinting(false)
    }
  }

  const handleStop = async () => {
    setMinting(false)
    setTX(undefined)
    setProgress(undefined)
    minerManager.stop();
    console.log("stop mint success!");
  }

  return (
    <Container maxWidth="lg">
      <div className="card">
        {!minting && (
          <div>
            {mintResult && (
              <div>Found nonce: {mintResult.nonce}, hash: {mintResult.hash}</div>
            )}

            {errorMsg && (
              <div style={{color: 'red'}}>Error: {errorMsg}</div>
            )}

            {tx && (
              <div>Mint ok, tx: {tx}</div>
            )}

            <Button variant="contained" onClick={() => handleMint(account)}>
              Mint
            </Button>
          </div>
        )}

        {minting && (
          <div>
            <div>
              Minting...
            </div>
            <div>
              {progress && progress.details && progress.details.map((item, index)=>(
                <div key={"item_" + index} style={{display: 'flex', justifyContent: 'space-between', fontFamily: "'Courier New', monospace"}}>
                  <div style={{width: '33%', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap'}}>Hash: {item.hash}</div>
                  <div style={{width: '33%'}}>Nonce: {item.nonce}</div>
                  <div style={{width: '33%'}}>{humanReadableHashrate(item.hashRate)}</div>
                </div>
              ))}
            </div>
            <Button variant="contained" onClick={() => handleStop()}>
              Stop
            </Button>
          </div>
        )}
      </div>
    </Container>
  )
}

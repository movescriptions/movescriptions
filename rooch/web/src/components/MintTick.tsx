'use client';
import { useState } from 'react'

import Button from '@mui/material/Button';
import Box from '@mui/material/Box';

import { arrayify } from "@ethersproject/bytes"
import { MinerManager, IMinerTask, IMintResult, IMintProgress } from '../miner'
import { humanReadableHashrate } from '../utils/hashRate'

import { movescriptionConfig } from '@/config/movescription'

/** SDK */
import { IAccount } from '@yubing744/rooch-sdk'
import { useRoochClient } from '@roochnetwork/rooch-sdk-kit'


const moveScriptionAddress = `${movescriptionConfig.movescriptionAddress}`
const mrc20TickInfoFunc = `${moveScriptionAddress}::movescription::get_tick_info`
const mrc20PowInputFunc = `${moveScriptionAddress}::movescription::pow_input`
const mrc20PowValidateFunc = `${moveScriptionAddress}::movescription::validate_pow`
const mrc20MintFunc = `${moveScriptionAddress}::mrc20::mint`


let minerManager = new MinerManager(4, 0);

export type MintTickProps = {
  account: IAccount,
  tick: string,
  amount: number,
}

export default function MintTick(props: MintTickProps) {
  const client = useRoochClient();
  const account = props.account;

  const [minting, setMinting] = useState(false);
  const [progress, setProgress] = useState<IMintProgress|undefined>(undefined);
  const [mintResult, setMintResult] = useState<IMintResult|undefined>(undefined);
  const [errorMsg, setErrorMsg] = useState<string|undefined>(undefined);
  const [tx, setTX] = useState<string|undefined>(undefined);

  const getPowInput = async (account: IAccount, tick: string, value: number) => {
    const resp = await client.executeViewFunction({
      funcId: mrc20PowInputFunc,
      tyArgs: [],
      args: [
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
      ]
    })

    console.log("getPowInput resp:", resp);

    if (resp.vm_status == 'Executed') {
      return resp.return_values?.[0]?.decoded_value as string;
    }

    throw new Error("get_pow_input_error:" + JSON.stringify(resp))
  }

  const getTickInfoObjectID = async (tick: string): Promise<any> => {
    const resp = await client.executeViewFunction({
      funcId: mrc20TickInfoFunc,
      tyArgs: [],
      args: [
        {
          type: 'Object',
          value: {
            address: moveScriptionAddress,
            module: 'movescription',
            name: 'TickRegistry',
          },
        },
        {
          type: 'String',
          value: tick,
        }
      ]
    })

    console.log("get_tick_info_object_id resp:", resp);

    if (resp.vm_status == 'Executed') {
      return resp.return_values?.[0]?.decoded_value;
    }

    throw new Error("get_tick_info_object_id_error:" + JSON.stringify(resp))
  }

  const getTickInfo = async (tick: string): Promise<any> => {
    const tickInfoObjectID = await getTickInfoObjectID(tick);
    const newData = await client.queryGlobalStates({
      filter: {
        object_id: tickInfoObjectID 
      },
      cursor: null,
      limit: 1,
      descending_order: true,
    })

    console.log("get_tick_info resp:", newData.data);

    if (newData.data.length > 0) {
      const tickInfo = newData.data[0].value.value;
      return {
        tick: tickInfo.tick,
        difficulty: parseInt(tickInfo.difficulty as string)
      }
    }

    throw new Error("get_tick_info_error:" + JSON.stringify(newData))
  }

  const validatePow = async (account: IAccount, tick: string, value: number, difficulty: number, nonce: number) => {
    const resp = await client.executeViewFunction({
      funcId: mrc20PowValidateFunc,
      tyArgs: [],
      args: [
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
      ]
    })

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

    const tick = props.tick;
    const amount = props.amount;

    console.log("account address:", account.getAddress());

    try {
      const tickInfo = await getTickInfo(tick);
      console.log("tickInfo:", tickInfo);

      const result = await searchNonce(account, tick, amount, tickInfo.difficulty)
      console.log("found nonce:", result.nonce, 'hash:', result.hash);

      if (!await validatePow(account, tick, amount, tickInfo.difficulty, result.nonce)) {
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
    <Box style={{display: 'flex', justifyContent: 'center'}}>
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
              {progress && progress.details && progress.details.map((item: any, index: number)=>(
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
    </Box>
  );
}

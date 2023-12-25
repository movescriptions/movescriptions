import { useState } from 'react'
import { Keccak256 } from "@hazae41/keccak256"
import './App.css'
//import { keccak256_gpu_batch } from 'keccak256-webgpu';

Keccak256.set(await Keccak256.fromMorax())

/** SDK */
import {
  RoochClient, DevChain, Account, Ed25519Keypair, PrivateKeyAuth,
  IAccount,
} from '@roochnetwork/rooch-sdk'

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

  const hash = (data: Uint8Array): Uint8Array=>{
    return Keccak256.get().tryHash(data).unwrap().copyAndDispose()
  }

  function appendU64ToUint8Array(array: Uint8Array, u64: bigint): Uint8Array {
    const tempArray = new Uint8Array(8);
    for (let i = 0; i < 8; i++) {
        tempArray[i] = Number((u64 & (BigInt(0xff) << BigInt(i * 8))) >> BigInt(i * 8));
    }
    const result = new Uint8Array(array.length + tempArray.length);
    result.set(array);
    result.set(tempArray, array.length);
    return result;
  }

  const matchDiffi = (_data: Uint8Array, _diff: number):boolean => {
    return true
  }

  const searchNonce = async (account: IAccount, tick: string, value: number, diff: number) => {
    const powInput = await getPowInput(account, tick, value)

    let nonce = new Date().getTime()
    while(powInput) {
      const data = hash(appendU64ToUint8Array(hash(powInput), BigInt(nonce)))
      if (matchDiffi(data, diff)) {
        return nonce
      }

      nonce++;
    }

    return 0
  }

  const handleMint = async (account: IAccount) => {
    setMinting(true)

    const nonce = await searchNonce(account, "move", 1000, 9)
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

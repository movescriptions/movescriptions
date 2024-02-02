import * as React from 'react';
import { useState } from 'react';
import Button from '@mui/material/Button';
import { useConnectWallet, useWalletStore } from '@roochnetwork/rooch-sdk-kit'

const formatAddress = (address: string) => {
  let shortAddress = address.substring(0, 6)
  shortAddress += '...'
  shortAddress += address.substring(address.length - 6, address.length)

  return shortAddress
}

export default function ConnectButton() {
  // ** States
  const [loading, setLoading] = useState(false)

  // ** Hooks
  const account = useWalletStore((state) => state.currentAccount)
  const { mutateAsync: connectWallet } = useConnectWallet()

  const handleConnect = async () => {
    setLoading(true)
    if (account === null) {
      await connectWallet()
    }

    setLoading(false)
  }
  
  return (
    <Button 
      disabled={loading}
      onClick={handleConnect}
      color="inherit"
      >
        {account === null ? 'connect' : formatAddress(account?.getAddress())}
    </Button>
  );
}
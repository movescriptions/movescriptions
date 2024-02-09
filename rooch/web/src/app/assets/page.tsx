'use client';
import * as React from 'react';
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';
import Box from '@mui/material/Box';
 
import UserAssets from "@/components/UserAssets"
import { RoochMultiChainID } from '@roochnetwork/rooch-sdk'
import { useWalletStore, WalletAccount, useResolveRoochAddress} from '@roochnetwork/rooch-sdk-kit'

export default function MyAssets() {
  const currentAccount = useWalletStore<WalletAccount | null>((store)=>store.currentAccount)

  let roochAddress = useResolveRoochAddress(
    currentAccount?.getAddress() ?? '',
    RoochMultiChainID.Bitcoin,
  )

  console.log("my rooch address:", roochAddress.data);

  return (
    <Container maxWidth="lg">
      <Typography variant="h4" component="h1" align="left" sx={{ mb: 2 }}>
        MRC20 Assets
      </Typography>

      <Box
        sx={{
          my: 4,
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          alignItems: 'center',
        }}
      >
        {roochAddress && roochAddress.data ? (
          <UserAssets address={roochAddress.data}></UserAssets>
        ) : (
          <Typography>Please connect wallet to view assets.</Typography>
        )}
      </Box>
    </Container>
  );
}

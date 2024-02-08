'use client';

import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';

import MintTick from '@/components/MintTick';
import { useCurrentSessionAccount } from '@roochnetwork/rooch-sdk-kit'


export default function Mint() {
  const sessionAccount = useCurrentSessionAccount();

  return (
    <Container maxWidth="lg">
      {sessionAccount ? (
        <MintTick account={sessionAccount} tick='move' amount={1000} difficulty={3}/>
      ):(
        <Typography>Please connect wallet to view assets.</Typography>
      )}
      
    </Container>
  )
}

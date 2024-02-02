'use client';
import * as React from 'react';
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';
import Box from '@mui/material/Box';
import Copyright from '@/components/Copyright';
 
import UserAssets from "@/components/UserAssets"
import { useCurrentSessionAccount } from '@roochnetwork/rooch-sdk-kit'

export default function MyAssets() {
  const account = useCurrentSessionAccount()

  return (
    <Container maxWidth="lg">
      <Box
        sx={{
          my: 4,
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          alignItems: 'center',
        }}
      >
        <Typography variant="h4" component="h1" sx={{ mb: 2 }}>
          MRC20 Assets
        </Typography>

        {account ? (
          <UserAssets address=''></UserAssets>
        ) : (
          <Typography>Please connect wallet to view assets.</Typography>
        )}

        <Copyright />
      </Box>
    </Container>
  );
}

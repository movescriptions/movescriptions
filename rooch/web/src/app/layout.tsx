'use client';
import * as React from 'react';
import { AppRouterCacheProvider } from '@mui/material-nextjs/v14-appRouter';
import { ThemeProvider } from '@mui/material/styles';
import CircularProgress from '@mui/material/CircularProgress'
import CssBaseline from '@mui/material/CssBaseline';
import theme from '@/theme';
import SessionGuard from '@/components/SessionGuard';

import {
  QueryClient,
  QueryClientProvider,
} from '@tanstack/react-query'

import { DevChain } from '@roochnetwork/rooch-sdk'
import { WalletProvider, RoochClientProvider, SupportChain } from '@roochnetwork/rooch-sdk-kit'

export default function RootLayout(props: { children: React.ReactNode }) {
  const queryClient = new QueryClient()

  return (
    <html lang="en">
      <body>
        <AppRouterCacheProvider options={{ enableCssLayer: true }}>
          <QueryClientProvider client={queryClient}>
            <RoochClientProvider defaultNetwork={DevChain}>
              <WalletProvider chain={SupportChain.BITCOIN} autoConnect={true} fallback={<CircularProgress />}>
                <ThemeProvider theme={theme}>
                  {/* CssBaseline kickstart an elegant, consistent, and simple baseline to build upon. */}
                  <CssBaseline />
                  <SessionGuard>
                    {props.children}
                  </SessionGuard>
                </ThemeProvider>
              </WalletProvider>
            </RoochClientProvider>
          </QueryClientProvider>
        </AppRouterCacheProvider>
      </body>
    </html>
  );
}

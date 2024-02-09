import * as React from 'react';
import { Metadata } from 'next'
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';
import Box from '@mui/material/Box';
import Link from '@mui/material/Link';
import NextLink from 'next/link';
import Copyright from '@/components/Copyright';

export const metadata: Metadata = {
  title: 'MoveScriptions',
}

export default function Home() {
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
          Demo
        </Typography>

        <Link href="/assets" color="secondary" component={NextLink}>
          Go to assets page
        </Link>

        <Copyright />
      </Box>
    </Container>
  );
}

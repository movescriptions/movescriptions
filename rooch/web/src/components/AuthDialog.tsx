import React, { useState } from 'react'
import {
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogContentText,
  DialogTitle,
  TextField,
} from '@mui/material'

import { movescriptionConfig } from '@/config/movescription'

interface Props {
  open: boolean
  onReqAuthorize: (scope: Array<string>, maxInactiveInterval: number) => void
  onLogout?: () => void
}

const defaultScope = [
  '0x1::*::*',
  '0x3::*::*',
  `${movescriptionConfig.movescriptionAddress}::*::*`,
]

export default function AuthDialog({ open, onReqAuthorize, onLogout }: Props) {
  const [scope, setScope] = useState<Array<string>>(defaultScope)
  const [maxInactiveInterval, setMaxInactiveInterval] = useState<number>(1200)

  const handleAuth = () => {
    onReqAuthorize && onReqAuthorize(scope, maxInactiveInterval)
  }

  return (
    <Dialog open={open} onClose={onLogout}>
      <DialogTitle>Session Authorize</DialogTitle>
      <DialogContent>
        <DialogContentText>
          The current session does not exist or has expired. Please authorize the creation of a new
          session.
        </DialogContentText>
        <TextField
          autoFocus
          margin="dense"
          id="scope"
          label="Scope"
          type="text"
          multiline
          fullWidth
          disabled
          variant="standard"
          value={scope.join('\n')}
          onChange={(event: React.ChangeEvent<HTMLInputElement>) => {
            setScope(event.target.value.split('\n'))
          }}
        />
        <TextField
          autoFocus
          margin="dense"
          id="max_inactive_interval"
          label="Max Inactive Interval"
          type="text"
          multiline
          fullWidth
          disabled
          variant="standard"
          value={maxInactiveInterval}
          onChange={(event: React.ChangeEvent<HTMLInputElement>) => {
            setMaxInactiveInterval(parseInt(event.target.value))
          }}
        />
      </DialogContent>
      <DialogActions>
        {onLogout ? <Button onClick={onLogout}>Logout</Button> : null}
        <Button onClick={handleAuth}>Authorize</Button>
      </DialogActions>
    </Dialog>
  )
}
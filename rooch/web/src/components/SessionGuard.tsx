import React, { ReactNode, useState } from 'react'
import AuthDialog from '@/components/AuthDialog'

// ** Hooks Import
import { useCurrentSessionAccount, useCreateSessionKey } from '@roochnetwork/rooch-sdk-kit'

interface SessionGuardProps {
  children: ReactNode
}

export default function SessionGuard(props: SessionGuardProps) {
  const { children } = props

  const sessionAccount = useCurrentSessionAccount()
  const { mutate: createSessionKey } = useCreateSessionKey()

  const handleAuth = (scope: Array<string>, maxInactiveInterval: number) => {
    // requestAuthorize && requestAuthorize(scope, maxInactiveInterval)
    createSessionKey({
      scope: scope,
      maxInactiveInterval: maxInactiveInterval,
    })
  }

  // const isSessionInvalid = () => {
  //   return !initialization && (account === undefined || account === null)
  // }

  return (
    <>
      <AuthDialog open={sessionAccount === null} onReqAuthorize={handleAuth} onLogout={close} />
      {children}
    </>
  )
}

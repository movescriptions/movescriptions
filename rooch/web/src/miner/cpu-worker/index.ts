
/* eslint-disable @typescript-eslint/no-explicit-any */
const ctx: Worker = self as any;
/* eslint-enable @typescript-eslint/no-explicit-any */

ctx.onmessage = async (event: MessageEvent<any>) => {
  const { type, payload } = event.data;
  console.log('[Explore]: worker handle message:', type, 'payload:', payload);
}

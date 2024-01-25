
export function humanReadableHashrate(hashrate: number): string {
  const units: string[] = ['H/s', 'KH/s', 'MH/s', 'GH/s', 'TH/s', 'PH/s', 'EH/s', 'ZH/s', 'YH/s'];
  let i: number = 0;
  while(hashrate >= 1000) {
      hashrate /= 1000;
      ++i;
  }
  return hashrate.toFixed(1) + ' ' + units[i];
}
import AccountBalanceIcon from '@mui/icons-material/AccountBalance';
import SportsCricketIcon from '@mui/icons-material/SportsCricket';
import HomeIcon from '@mui/icons-material/Home';

export type SiteConfig = typeof siteConfig

export const siteConfig = {
  name: "MRC20",
  description:
    "We provide MRC20 smart inscription mint service.",
  mainNav: [
    {
      title: "Home",
      href: "/",
      icon: <HomeIcon/>
    },
    {
      title: "Mint",
      href: "/mint",
      icon: <SportsCricketIcon/>
    },
    {
      title: "My Assets",
      href: "/assets",
      icon: <AccountBalanceIcon/>
    },
  ],
  links: {
    twitter: "https://twitter.com/MoveScriptions",
    github: "https://github.com/movescriptions/movescriptions",
    docs: "",
  },
}

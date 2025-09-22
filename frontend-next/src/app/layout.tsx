import { Inter, EB_Garamond } from 'next/font/google'
import './globals.css'

const inter = Inter({
  subsets: ['latin'],
  variable: '--font-inter',
  display: 'swap'
})

const eb_garamond = EB_Garamond({
  subsets: ['latin'],
  weight: ['400', '500', '600', '700', '800'],
  variable: '--font-eb-garamond',
  display: 'swap'
})

// SF Pro system font variable
const sfPro = {
  variable: '--font-sf-pro'
}

export const metadata = {
  title: 'Tally',
  description: 'build better habits',
  icons: {
    icon: '/favicon.ico',
  },
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${inter.variable} ${eb_garamond.variable} ${sfPro.variable} font-sans overflow-x-hidden`}>
        {children}
      </body>
    </html>
  )
} 
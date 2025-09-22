import { HTMLAttributes } from 'react'
import { cn } from '@/utils/cn'

interface ContainerProps extends HTMLAttributes<HTMLDivElement> {
  size?: 'default' | 'small' | 'large'
}

export function Container({
  children,
  className,
  size = 'default',
  ...props
}: ContainerProps) {
  return (
    <div
      className={cn(
        'mx-auto w-full px-4 md:px-6 lg:px-8',
        {
          'max-w-screen-xl': size === 'default',
          'max-w-screen-lg': size === 'small',
          'max-w-screen-2xl': size === 'large',
        },
        className
      )}
      {...props}
    >
      {children}
    </div>
  )
} 
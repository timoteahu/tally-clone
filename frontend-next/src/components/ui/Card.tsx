import { HTMLAttributes, forwardRef } from 'react'
import { cn } from '@/utils/cn'

interface CardProps extends HTMLAttributes<HTMLDivElement> {
  noPadding?: boolean
  noBorder?: boolean
  blur?: boolean
}

const Card = forwardRef<HTMLDivElement, CardProps>(
  ({ className, children, noPadding = false, noBorder = false, blur = false, ...props }, ref) => {
    return (
      <div
        ref={ref}
        className={cn(
          'rounded-2xl bg-surface-foreground',
          !noBorder && 'gradient-border',
          !noPadding && 'p-6',
          blur && 'card-blur',
          className
        )}
        {...props}
      >
        {children}
      </div>
    )
  }
)

Card.displayName = 'Card'

export { Card } 
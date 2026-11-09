import { useEffect } from 'react'
import App from './App'
import { resolveSiteRoute } from './lib/routes'

function UnavailablePage() {
  useEffect(() => {
    const title = document.title
    document.title = 'Page unavailable | Hash Fleet'
    const robots = document.createElement('meta')
    robots.name = 'robots'
    robots.content = 'noindex'
    document.head.append(robots)
    return () => { document.title = title; robots.remove() }
  }, [])

  return <>
    <a className="skip-link" href="#main">Skip to content</a>
    <main id="main" className="route-unavailable" data-route-unavailable>
      <a className="brand" href="/" aria-label="Hash Fleet home"><img src="/images/brand.png" alt="" width="42" height="42" /><span>Hash<span className="brand-light">Fleet</span><i className="brand-period">.</i></span></a>
      <span className="eyebrow">ONE SITE. YOUR WAY BACK.</span>
      <h1>This page isn’t available.</h1>
      <p>The address you opened is not a public Hash Fleet page. Protected files and service endpoints are not part of the website.</p>
      <a className="button button-primary" href="/">Back to Hash Fleet</a>
      <nav aria-label="Explore the product demos"><a href="/demo/mac">Mac demo</a><a href="/demo/iphone">iPhone demo</a><a href="/demo/terminal">Terminal demo</a></nav>
    </main>
  </>
}

export default function SiteEntry() {
  const route = resolveSiteRoute(window.location.pathname)
  if (route.kind === 'unavailable') return <UnavailablePage />
  return route.kind === 'demo' ? <App initialPlatform={route.platform} startAtDemo /> : <App />
}

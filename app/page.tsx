import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { ArrowRight, Check, Smartphone, Star, Users, Zap } from "lucide-react"
import Image from "next/image"

export default function LandingPage() {
  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-b border-border">
        <div className="container mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Image
              src="/assets/construction-icon.webp"
              alt="Binay Tech"
              width={40}
              height={40}
              className="rounded-lg"
            />
            <span className="text-xl font-semibold text-foreground">Binay Tech</span>
          </div>
          <nav className="hidden md:flex items-center gap-8">
            <a href="#features" className="text-sm text-muted-foreground hover:text-foreground transition-colors">
              Features
            </a>
            <a href="#benefits" className="text-sm text-muted-foreground hover:text-foreground transition-colors">
              Benefits
            </a>
            <a href="#download" className="text-sm text-muted-foreground hover:text-foreground transition-colors">
              Download
            </a>
          </nav>
          <Button variant="outline" className="hidden md:flex bg-transparent" asChild>
            <a
              href="https://play.google.com/store/apps/details?id=com.binaytech.app"
              target="_blank"
              rel="noopener noreferrer"
            >
              Get Started
            </a>
          </Button>
        </div>
      </header>

      {/* Hero Section */}
      <section className="container mx-auto px-4 py-24 md:py-32">
        <div className="max-w-4xl mx-auto text-center">
          <div className="flex justify-center mb-8">
            <Image
              src="/assets/construction-icon.webp"
              alt="Binay Tech Construction"
              width={120}
              height={120}
              className="rounded-2xl"
            />
          </div>
          <div className="inline-block mb-6 px-4 py-2 rounded-full bg-accent/50 text-accent-foreground text-sm">
            Now Available on Android
          </div>
          <h1 className="text-5xl md:text-7xl font-bold text-foreground mb-6 text-balance">
            The Complete Platform for Your Mobile Needs
          </h1>
          <p className="text-xl text-muted-foreground mb-8 max-w-2xl mx-auto text-pretty leading-relaxed">
            Experience the power of modern technology with Binay Tech. Build, deploy, and scale your digital presence
            with our innovative mobile application.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <a
              href="https://play.google.com/store/apps/details?id=com.binaytech.app"
              target="_blank"
              rel="noopener noreferrer"
            >
              <Image
                src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png"
                alt="Get it on Google Play"
                width={200}
                height={60}
                className="hover:opacity-80 transition-opacity"
              />
            </a>
            <Button size="lg" variant="outline" className="w-full sm:w-auto gap-2 bg-transparent" asChild>
              <a href="#features">
                Learn More
                <ArrowRight className="w-5 h-5" />
              </a>
            </Button>
          </div>
          <p className="text-sm text-muted-foreground mt-6">Free to download. No credit card required.</p>
        </div>
      </section>

      {/* Stats Section */}
      <section className="border-y border-border">
        <div className="container mx-auto px-4 py-16">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
            <div className="text-center">
              <div className="text-4xl font-bold text-foreground mb-2">50K+</div>
              <div className="text-sm text-muted-foreground">Active Users</div>
            </div>
            <div className="text-center">
              <div className="text-4xl font-bold text-foreground mb-2">98%</div>
              <div className="text-sm text-muted-foreground">Satisfaction Rate</div>
            </div>
            <div className="text-center">
              <div className="text-4xl font-bold text-foreground mb-2">4.8★</div>
              <div className="text-sm text-muted-foreground">App Store Rating</div>
            </div>
            <div className="text-center">
              <div className="text-4xl font-bold text-foreground mb-2">24/7</div>
              <div className="text-sm text-muted-foreground">Support Available</div>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className="container mx-auto px-4 py-24">
        <div className="text-center mb-16">
          <h2 className="text-4xl md:text-5xl font-bold text-foreground mb-4 text-balance">
            Everything You Need in One Place
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto text-pretty">
            Powerful features designed to streamline your workflow and enhance productivity.
          </p>
        </div>
        <div className="grid md:grid-cols-3 gap-8">
          <Card className="p-8 border-border bg-card hover:shadow-lg transition-shadow">
            <div className="w-12 h-12 rounded-lg bg-primary/10 flex items-center justify-center mb-6">
              <Zap className="w-6 h-6 text-primary" />
            </div>
            <h3 className="text-2xl font-bold text-card-foreground mb-3">Lightning Fast</h3>
            <p className="text-muted-foreground leading-relaxed">
              Optimized performance ensures smooth operation and instant response times for all your tasks.
            </p>
          </Card>
          <Card className="p-8 border-border bg-card hover:shadow-lg transition-shadow">
            <div className="w-12 h-12 rounded-lg bg-primary/10 flex items-center justify-center mb-6">
              <Smartphone className="w-6 h-6 text-primary" />
            </div>
            <h3 className="text-2xl font-bold text-card-foreground mb-3">Mobile First</h3>
            <p className="text-muted-foreground leading-relaxed">
              Built from the ground up for mobile devices, providing the best possible experience on any screen.
            </p>
          </Card>
          <Card className="p-8 border-border bg-card hover:shadow-lg transition-shadow">
            <div className="w-12 h-12 rounded-lg bg-primary/10 flex items-center justify-center mb-6">
              <Users className="w-6 h-6 text-primary" />
            </div>
            <h3 className="text-2xl font-bold text-card-foreground mb-3">Team Collaboration</h3>
            <p className="text-muted-foreground leading-relaxed">
              Work together seamlessly with powerful collaboration tools designed for modern teams.
            </p>
          </Card>
        </div>
      </section>

      {/* Benefits Section */}
      <section id="benefits" className="bg-muted/30 py-24">
        <div className="container mx-auto px-4">
          <div className="grid md:grid-cols-2 gap-16 items-center">
            <div>
              <h2 className="text-4xl md:text-5xl font-bold text-foreground mb-6 text-balance">
                Built for Innovation and Growth
              </h2>
              <p className="text-lg text-muted-foreground mb-8 leading-relaxed">
                Transform the way you work with cutting-edge technology that adapts to your needs.
              </p>
              <ul className="space-y-4">
                <li className="flex items-start gap-3">
                  <Check className="w-6 h-6 text-primary flex-shrink-0 mt-1" />
                  <div>
                    <div className="font-semibold text-foreground mb-1">Seamless Integration</div>
                    <div className="text-muted-foreground">
                      Connect with your favorite tools and services effortlessly.
                    </div>
                  </div>
                </li>
                <li className="flex items-start gap-3">
                  <Check className="w-6 h-6 text-primary flex-shrink-0 mt-1" />
                  <div>
                    <div className="font-semibold text-foreground mb-1">Advanced Security</div>
                    <div className="text-muted-foreground">
                      Enterprise-grade security to keep your data safe and protected.
                    </div>
                  </div>
                </li>
                <li className="flex items-start gap-3">
                  <Check className="w-6 h-6 text-primary flex-shrink-0 mt-1" />
                  <div>
                    <div className="font-semibold text-foreground mb-1">Regular Updates</div>
                    <div className="text-muted-foreground">
                      Continuous improvements and new features delivered regularly.
                    </div>
                  </div>
                </li>
              </ul>
            </div>
            <div className="relative">
              <Card className="p-8 border-border bg-card">
                <div className="aspect-square rounded-lg bg-gradient-to-br from-primary/20 to-accent/20 flex items-center justify-center">
                  <Image
                    src="/assets/construction-icon.webp"
                    alt="Binay Tech App"
                    width={300}
                    height={300}
                    className="rounded-lg"
                  />
                </div>
              </Card>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section id="download" className="container mx-auto px-4 py-24">
        <Card className="p-12 md:p-16 text-center border-border bg-card">
          <h2 className="text-4xl md:text-5xl font-bold text-card-foreground mb-4 text-balance">
            Ready to Get Started?
          </h2>
          <p className="text-lg text-muted-foreground mb-8 max-w-2xl mx-auto text-pretty">
            Join thousands of users who are already experiencing the future of mobile technology.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <a
              href="https://play.google.com/store/apps/details?id=com.binaytech.app"
              target="_blank"
              rel="noopener noreferrer"
            >
              <Image
                src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png"
                alt="Get it on Google Play"
                width={200}
                height={60}
                className="hover:opacity-80 transition-opacity"
              />
            </a>
          </div>
          <div className="flex items-center justify-center gap-1 mt-6">
            {[...Array(5)].map((_, i) => (
              <Star key={i} className="w-5 h-5 fill-primary text-primary" />
            ))}
            <span className="ml-2 text-sm text-muted-foreground">4.8 out of 5 stars</span>
          </div>
        </Card>
      </section>

      {/* Footer */}
      <footer className="border-t border-border py-12">
        <div className="container mx-auto px-4">
          <div className="grid md:grid-cols-4 gap-8 mb-8">
            <div>
              <div className="flex items-center gap-2 mb-4">
                <Image
                  src="/assets/construction-icon.webp"
                  alt="Binay Tech"
                  width={32}
                  height={32}
                  className="rounded-lg"
                />
                <span className="font-semibold text-foreground">Binay Tech</span>
              </div>
              <p className="text-sm text-muted-foreground">Building the future of mobile technology.</p>
            </div>
            <div>
              <h4 className="font-semibold text-foreground mb-4">Product</h4>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li>
                  <a href="#" className="hover:text-foreground transition-colors">
                    Features
                  </a>
                </li>
                <li>
                  <a href="#" className="hover:text-foreground transition-colors">
                    Pricing
                  </a>
                </li>
                <li>
                  <a href="#" className="hover:text-foreground transition-colors">
                    Updates
                  </a>
                </li>
              </ul>
            </div>
            <div>
              <h4 className="font-semibold text-foreground mb-4">Company</h4>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li>
                  <a href="#" className="hover:text-foreground transition-colors">
                    About
                  </a>
                </li>
                <li>
                  <a href="#" className="hover:text-foreground transition-colors">
                    Blog
                  </a>
                </li>
                <li>
                  <a href="#" className="hover:text-foreground transition-colors">
                    Contact
                  </a>
                </li>
              </ul>
            </div>
            <div>
              <h4 className="font-semibold text-foreground mb-4">Legal</h4>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li>
                  <a href="#" className="hover:text-foreground transition-colors">
                    Privacy
                  </a>
                </li>
                <li>
                  <a href="#" className="hover:text-foreground transition-colors">
                    Terms
                  </a>
                </li>
                <li>
                  <a href="#" className="hover:text-foreground transition-colors">
                    Security
                  </a>
                </li>
              </ul>
            </div>
          </div>
          <div className="pt-8 border-t border-border text-center text-sm text-muted-foreground">
            © 2025 Binay Tech. All rights reserved.
          </div>
        </div>
      </footer>
    </div>
  )
}

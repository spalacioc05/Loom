import { BookOpen, Download, Headphones, Upload, Volume2, Sparkles } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"

export default function LoomLandingPage() {
  return (
    <div className="min-h-screen bg-[#1a1a1f]">
      {/* Navigation */}
      <nav className="fixed top-0 w-full z-50 bg-[#1a1a1f]/80 backdrop-blur-md border-b border-white/5">
        <div className="container mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="size-10 rounded-xl bg-gradient-to-br from-cyan-400 to-blue-500 flex items-center justify-center">
              <Volume2 className="size-6 text-white" />
            </div>
            <span className="text-2xl font-bold text-white">Loom</span>
          </div>
          <div className="hidden md:flex items-center gap-8">
            <a href="#inicio" className="text-gray-400 hover:text-cyan-400 transition-colors">
              Inicio
            </a>
            <a href="#caracteristicas" className="text-gray-400 hover:text-cyan-400 transition-colors">
              Características
            </a>
            <a href="#mision" className="text-gray-400 hover:text-cyan-400 transition-colors">
              Misión
            </a>
            <a href="#descargar" className="text-gray-400 hover:text-cyan-400 transition-colors">
              Descargar
            </a>
          </div>
        </div>
      </nav>

      {/* Hero Section */}
      <section id="inicio" className="pt-32 pb-20 px-4">
        <div className="container mx-auto max-w-6xl">
          <div className="text-center space-y-8">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-cyan-500/10 border border-cyan-400/20">
              <Sparkles className="size-4 text-cyan-400" />
              <span className="text-cyan-400 text-sm font-medium">{"Lectura con voces naturales"}</span>
            </div>

            <h1 className="text-5xl md:text-7xl font-bold text-white leading-tight text-balance">
              {"La revolución en la "}
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 to-blue-500">
                {"lectura auditiva"}
              </span>
            </h1>

            <p className="text-xl text-gray-400 max-w-3xl mx-auto leading-relaxed text-pretty">
              {
                "Descubre una nueva forma de disfrutar tus libros favoritos. Loom transforma cualquier texto en una experiencia auditiva con voces increíblemente naturales y humanas."
              }
            </p>

            <div className="flex flex-col sm:flex-row gap-4 justify-center items-center pt-4">
              <Button
                size="lg"
                className="bg-cyan-500 hover:bg-cyan-600 text-white px-8 py-6 text-lg rounded-xl shadow-lg shadow-cyan-500/25"
              >
                <Download className="size-5 mr-2" />
                {"Descargar APK"}
              </Button>

            </div>
          </div>

          
        </div>
      </section>

      {/* Features Section */}
      <section id="caracteristicas" className="py-20 px-4 bg-[#14141a]">
        <div className="container mx-auto max-w-6xl">
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-5xl font-bold text-white mb-4 text-balance">
              {"Características que "}
              <span className="text-cyan-400">{"transforman"}</span>
            </h2>
            <p className="text-gray-400 text-lg max-w-2xl mx-auto text-pretty">
              {"Todo lo que necesitas para una experiencia de lectura auditiva perfecta"}
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
            <Card className="bg-gradient-to-br from-gray-800/50 to-gray-900/50 border-white/10 p-6 hover:border-cyan-400/50 transition-all duration-300">
              <div className="size-12 rounded-xl bg-cyan-500/10 flex items-center justify-center mb-4">
                <Volume2 className="size-6 text-cyan-400" />
              </div>
              <h3 className="text-xl font-semibold text-white mb-2">{"Voces Naturales"}</h3>
              <p className="text-gray-400 leading-relaxed">
                {"Tecnología de voz avanzada que suena increíblemente humana, con tonalidades y pausas naturales."}
              </p>
            </Card>

            <Card className="bg-gradient-to-br from-gray-800/50 to-gray-900/50 border-white/10 p-6 hover:border-cyan-400/50 transition-all duration-300">
              <div className="size-12 rounded-xl bg-cyan-500/10 flex items-center justify-center mb-4">
                <Upload className="size-6 text-cyan-400" />
              </div>
              <h3 className="text-xl font-semibold text-white mb-2">{"Sube tus PDFs"}</h3>
              <p className="text-gray-400 leading-relaxed">
                {"Importa tus propios documentos y libros en PDF para escucharlos con tu voz favorita."}
              </p>
            </Card>

            <Card className="bg-gradient-to-br from-gray-800/50 to-gray-900/50 border-white/10 p-6 hover:border-cyan-400/50 transition-all duration-300">
              <div className="size-12 rounded-xl bg-cyan-500/10 flex items-center justify-center mb-4">
                <BookOpen className="size-6 text-cyan-400" />
              </div>
              <h3 className="text-xl font-semibold text-white mb-2">{"Amplia Biblioteca"}</h3>
              <p className="text-gray-400 leading-relaxed">
                {"Accede a múltiples categorías de libros y encuentra siempre algo nuevo que escuchar."}
              </p>
            </Card>

            <Card className="bg-gradient-to-br from-gray-800/50 to-gray-900/50 border-white/10 p-6 hover:border-cyan-400/50 transition-all duration-300">
              <div className="size-12 rounded-xl bg-cyan-500/10 flex items-center justify-center mb-4">
                <Headphones className="size-6 text-cyan-400" />
              </div>
              <h3 className="text-xl font-semibold text-white mb-2">{"Aprendizaje Auditivo"}</h3>
              <p className="text-gray-400 leading-relaxed">
                {"Ideal para personas que aprenden mejor escuchando. Comprende más mientras haces otras actividades."}
              </p>
            </Card>

            <Card className="bg-gradient-to-br from-gray-800/50 to-gray-900/50 border-white/10 p-6 hover:border-cyan-400/50 transition-all duration-300">
              <div className="size-12 rounded-xl bg-cyan-500/10 flex items-center justify-center mb-4">
                <Sparkles className="size-6 text-cyan-400" />
              </div>
              <h3 className="text-xl font-semibold text-white mb-2">{"Personalización"}</h3>
              <p className="text-gray-400 leading-relaxed">
                {"Elige entre diferentes voces y ajusta la velocidad de lectura según tu preferencia."}
              </p>
            </Card>

            <Card className="bg-gradient-to-br from-gray-800/50 to-gray-900/50 border-white/10 p-6 hover:border-cyan-400/50 transition-all duration-300">
              <div className="size-12 rounded-xl bg-cyan-500/10 flex items-center justify-center mb-4">
                <Download className="size-6 text-cyan-400" />
              </div>
              <h3 className="text-xl font-semibold text-white mb-2">{"Seguimiento de Progreso"}</h3>
              <p className="text-gray-400 leading-relaxed">
                {"Mantén un registro de tus libros leídos y retoma donde dejaste fácilmente."}
              </p>
            </Card>
          </div>
        </div>
      </section>

      {/* Mission Section */}
      <section id="mision" className="py-20 px-4">
        <div className="container mx-auto max-w-6xl">
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            <div className="space-y-6">
              <div className="inline-block px-4 py-2 rounded-full bg-cyan-500/10 border border-cyan-400/20">
                <span className="text-cyan-400 text-sm font-medium">{"Nuestra Misión"}</span>
              </div>
              <h2 className="text-4xl md:text-5xl font-bold text-white text-balance">
                {"Democratizar el acceso a la "}
                <span className="text-cyan-400">{"lectura"}</span>
              </h2>
              <p className="text-gray-400 text-lg leading-relaxed">
                {
                  "En Loom, creemos que la lectura no debe ser una barrera para nadie. Nuestra misión es hacer que el conocimiento y las historias sean accesibles para todos, especialmente para aquellos que aprenden mejor escuchando."
                }
              </p>
              <p className="text-gray-400 text-lg leading-relaxed">
                {
                  "Queremos eliminar la fricción entre el contenido escrito y la comprensión, utilizando tecnología de voz natural que hace que escuchar un libro sea tan placentero como una conversación con un amigo."
                }
              </p>
            </div>
            <div className="relative">
              <div className="absolute inset-0 bg-gradient-to-r from-cyan-500/20 to-blue-500/20 blur-3xl" />
              <Card className="relative bg-gradient-to-br from-gray-800/50 to-gray-900/50 border-white/10 p-8">
                <img src="/person-wearing-headphones-reading-on-mobile-device.jpg" alt="Person enjoying audiobooks" className="w-full rounded-xl" />
              </Card>
            </div>
          </div>
        </div>
      </section>

      {/* Vision Section */}
      <section className="py-20 px-4 bg-[#14141a]">
        <div className="container mx-auto max-w-6xl">
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            <div className="relative order-2 lg:order-1">
              <div className="absolute inset-0 bg-gradient-to-r from-blue-500/20 to-cyan-500/20 blur-3xl" />
              <Card className="relative bg-gradient-to-br from-gray-800/50 to-gray-900/50 border-white/10 p-8">
                <img src="/futuristic-digital-library-with-glowing-books-and-.jpg" alt="Future of reading" className="w-full rounded-xl" />
              </Card>
            </div>
            <div className="space-y-6 order-1 lg:order-2">
              <div className="inline-block px-4 py-2 rounded-full bg-blue-500/10 border border-blue-400/20">
                <span className="text-blue-400 text-sm font-medium">{"Nuestra Visión"}</span>
              </div>
              <h2 className="text-4xl md:text-5xl font-bold text-white text-balance">
                {"El futuro de la lectura es "}
                <span className="text-cyan-400">{"auditiva"}</span>
              </h2>
              <p className="text-gray-400 text-lg leading-relaxed">
                {
                  "Visualizamos un mundo donde cada persona puede acceder al conocimiento de la forma que mejor se adapte a su estilo de aprendizaje. Un mundo donde la lectura no es solo visual, sino una experiencia multisensorial."
                }
              </p>
              <p className="text-gray-400 text-lg leading-relaxed">
                {
                  "Queremos ser la plataforma líder en lectura auditiva, expandiendo constantemente nuestra biblioteca y mejorando la calidad de nuestras voces para ofrecer la experiencia más natural y envolvente posible."
                }
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Download Section */}
      <section id="descargar" className="py-20 px-4">
        <div className="container mx-auto max-w-4xl">
          <div className="relative">
            <div className="absolute inset-0 bg-gradient-to-r from-cyan-500/20 to-blue-500/20 blur-3xl" />
            <Card className="relative bg-gradient-to-br from-gray-800/50 to-gray-900/50 border-cyan-400/30 p-12 text-center">
              <div className="space-y-6">
                <div className="size-20 mx-auto rounded-2xl bg-gradient-to-br from-cyan-400 to-blue-500 flex items-center justify-center">
                  <Download className="size-10 text-white" />
                </div>
                <h2 className="text-4xl md:text-5xl font-bold text-white text-balance">{"Descarga Loom ahora"}</h2>
                <p className="text-gray-400 text-lg max-w-2xl mx-auto text-pretty">
                  {
                    "Comienza tu viaje en la lectura auditiva hoy. Descarga el APK y descubre una nueva forma de disfrutar los libros."
                  }
                </p>
                <div className="pt-4">
                  <Button
                    size="lg"
                    className="bg-gradient-to-r from-cyan-500 to-blue-500 hover:from-cyan-600 hover:to-blue-600 text-white px-12 py-7 text-xl rounded-xl shadow-2xl shadow-cyan-500/25"
                  >
                    <Download className="size-6 mr-3" />
                    {"Descargar APK"}
                  </Button>
                  <p className="text-sm text-gray-500 mt-4">{"Compatible con Android 8.0 o superior"}</p>
                </div>
              </div>
            </Card>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-12 px-4 border-t border-white/5">
        <div className="container mx-auto max-w-6xl">
          <div className="flex flex-col md:flex-row justify-between items-center gap-6">
            <div className="flex items-center gap-2">
              <div className="size-10 rounded-xl bg-gradient-to-br from-cyan-400 to-blue-500 flex items-center justify-center">
                <Volume2 className="size-6 text-white" />
              </div>
              <span className="text-2xl font-bold text-white">Loom</span>
            </div>
            <p className="text-gray-400 text-center">{"© 2025 Loom. Todos los derechos reservados."}</p>
            <div className="flex gap-6">
              <a href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">
                {"Privacidad"}
              </a>
              <a href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">
                {"Términos"}
              </a>
              <a href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">
                {"Contacto"}
              </a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  )
}

require "erb"

module ViewRenderer
  VIEW_ROOT = File.expand_path("views", __dir__)

  def render_view(template, locals = {})
    ViewContext.new(self, locals).render(template)
  end

  class ViewContext
    def initialize(app, locals = {})
      @app = app
      @locals = locals
      locals.each do |key, value|
        instance_variable_set(:"@#{key}", value)
        define_singleton_method(key) { instance_variable_get(:"@#{key}") }
      end
    end

    def render(template, locals = {})
      context = locals.empty? ? self : self.class.new(@app, @locals.merge(locals))
      ERB.new(File.read(template_path(template)), trim_mode: "-").result(context.instance_eval { binding })
    end

    def partial(template, locals = {})
      render(template, locals)
    end

    def method_missing(name, *args, **kwargs, &block)
      return @app.send(name, *args, **kwargs, &block) if @app.respond_to?(name, true)

      super
    end

    def respond_to_missing?(name, include_private = false)
      @app.respond_to?(name, true) || super
    end

    private

    def template_path(template)
      path = File.expand_path("#{template}.erb", VIEW_ROOT)
      raise "View escapes view root: #{template}" unless path.start_with?("#{VIEW_ROOT}/")
      raise "Missing view template: #{template}" unless File.file?(path)

      path
    end
  end
end

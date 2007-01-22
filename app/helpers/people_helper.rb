module PeopleHelper
  def linkify(text, attribute)
    text.split(/,\s*/).map do |item|
      link_to h(item), {:action => 'search', attribute => item}, :class => 'no-underline'
    end.join ', '
  end
end

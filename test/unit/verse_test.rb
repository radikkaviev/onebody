require_relative '../test_helper'

class VerseTest < ActiveSupport::TestCase
  def setup
    @verse = Verse.create(reference: '1 John 1:9', text: 'test')
  end

  should "find an existing verse by reference" do
    v = Verse.find(@verse.reference)
    assert_equal 'test', v.text
  end

  should "find an existing verse by id" do
    v = Verse.find(@verse.id)
    assert_equal 'test', v.text
  end

  should "create a verse by reference" do
    v = Verse.find('1 John 1:9')
    assert_equal 'test', v.text
  end

  should "link verses in a body of text" do
    text = <<-END
      Here is a verse: John 3:16.
      Mark 1:1 is another verse.
      Here is a complex verse: John 3:16-4:2
      Another complex verse: Romans 12:5-6;13:9
      Romans 12 should be NIV and
      Romans 12 (MSG) should be The Message
    END
    linked = Verse.link_references_in_text(text)
    assert_equal 6, text.scan(/<a href/).length
    assert linked.index('http://bible.gospelcom.net/cgi-bin/bible?passage=Romans+12&version=NIV')
    assert linked.index('http://bible.gospelcom.net/cgi-bin/bible?passage=Romans+12&version=MSG')
  end

  should "normalize reference" do
    assert_equal "3 John 1:1", Verse.normalize_reference("3 john 1:1")
    assert_equal "2 Chronicles 10:1", Verse.normalize_reference("ii chronicles 10:1")
    assert_equal "John 3:16", Verse.normalize_reference("john 3:16")
    assert_equal "Song of Solomon 1:1", Verse.normalize_reference("Song of Solomon 1:1")
  end

end

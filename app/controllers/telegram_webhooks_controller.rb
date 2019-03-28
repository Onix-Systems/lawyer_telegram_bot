class TelegramWebhooksController < Telegram::Bot::UpdatesController
  include Telegram::Bot::UpdatesController::MessageContext
  include Concerns::Owners
  include Concerns::DocumentsType

  def start!(*)
    init_session
    start_message_text = "*Привіт, #{user['first_name']}!* Я Ваш персональний юрист!\n" \
                         "Я допоможу Вам швидко знайти будь-яку юридичну інформацію.\nПочнемо!"
    respond_with :message, text: start_message_text, parse_mode: 'Markdown'

    select_state_message = 'Мені потрібна додаткова інформація, перед початком пошуку:'
    respond_with :message, text: select_state_message, reply_markup: {
      inline_keyboard: [[{ text: 'Ключові слова', callback_data: 'keywords' },
                         { text: 'Видавництво', callback_data: 'owner' }],
                        [{ text: 'Тип документу', callback_data: 'document_type' },
                         { text: 'Тип пошуку', callback_data: 'search_type' }]],
      resize_keyboard: true,
      one_time_keyboard: true,
      selective: true
    }
  end

  def callback_query(data)
    case data
    when 'keywords' then keywords!
    when 'owner' then owner!
    when 'document_type' then document_type!
    when 'search_type' then search_type!
    when 'start_serch' then start_search!
    when 'restart' then start!
    when 'view_session_result' then view_session_result!
    else
      answer_callback_query t('.no_alert')
    end
  end

  def current_keyboard
    done = "\u{2705}"
    if can_search?
      [[{ text: 'Шукати', callback_data: 'start_serch' }],
       [{ text: 'Почати спочатку', callback_data: 'restart' }]]
    else
      [[{ text: "Ключові слова #{done if session[:keywords].present?}", callback_data: 'keywords' },
        { text: "Видавництво #{done if session[:owner].present?}", callback_data: 'owner' }],
       [{ text: "Тип документу #{done if session[:document_type].present?}", callback_data: 'document_type' },
        { text: "Тип пошуку #{done if session[:search_type].present?}", callback_data: 'search_type' }]]
      end
  end

  def can_search?
    %i[keywords owner document_type search_type].each do |key|
      return false if session[key].blank?
    end
    true
  end

  def keywords!(data = nil, *)
    if data
      session[:keywords] = current_callback_message
      select_state_message = 'Продовжимо:'
      respond_with :message, text: select_state_message, reply_markup: {
        inline_keyboard: current_keyboard,
        resize_keyboard: true,
        one_time_keyboard: true,
        selective: true
      }
    else
      save_context :keywords!
      respond_with :message, text: 'Введіть ключові слова через пробіл(не більше чотирьох): '
    end
  end

  def owner!(data = nil, *)
    if data
      if current_callback_message == 'Більше видавництв'
        save_context :owner!
        list_full = (owners_list_main.values[0...-1] + additional_owners_list.values).each_slice(2).to_a
        respond_with :message, text: 'Оберіть з розширеного списку:', reply_markup: {
          keyboard: list_full,
          resize_keyboard: true,
          one_time_keyboard: true,
          selective: true
        }
      else
        session[:owner] = current_callback_message
        select_state_message = 'Продовжимо:'
        respond_with :message, text: select_state_message, reply_markup: {
          inline_keyboard: current_keyboard,
          resize_keyboard: true,
          one_time_keyboard: true,
          selective: true
        }
      end
    else
      save_context :owner!
      list = owners_list_main.values.each_slice(2).to_a
      respond_with :message, text: 'Оберіть видавництво:', reply_markup: {
        keyboard: list,
        resize_keyboard: true,
        one_time_keyboard: true,
        selective: true
      }
    end
  end

  def document_type!(data = nil, *)
    if data
      if current_callback_message == 'Більше документів'
        save_context :document_type!
        list_full = (document_list_main.values[0...-1] + additional_documents_list.values).each_slice(2).to_a
        respond_with :message, text: 'Оберіть з розширеного списку:', reply_markup: {
          keyboard: list_full,
          resize_keyboard: true,
          one_time_keyboard: true,
          selective: true
        }
      else
        session[:document_type] = current_callback_message
        select_state_message = 'Продовжимо:'
        respond_with :message, text: select_state_message, reply_markup: {
          inline_keyboard: current_keyboard,
          resize_keyboard: true,
          one_time_keyboard: true,
          selective: true
        }
      end
    else
      save_context :document_type!
      list = document_list_main.values.each_slice(2).to_a
      respond_with :message, text: 'Оберіть тип документу:', reply_markup: {
        keyboard: list,
        resize_keyboard: true,
        one_time_keyboard: true,
        selective: true
      }
    end
  end

  def search_type!(data = nil, *)
    if data
      session[:search_type] = current_callback_message
      select_state_message = 'Продовжимо:'
      respond_with :message, text: select_state_message, reply_markup: {
        inline_keyboard: current_keyboard,
        resize_keyboard: true,
        one_time_keyboard: true,
        selective: true
      }
    else
      save_context :search_type!
      list = search_type_list.values.each_slice(1).to_a
      respond_with :message, text: 'Оберіть тип пошуку:', reply_markup: {
        keyboard: list,
        resize_keyboard: true,
        one_time_keyboard: true,
        selective: true
      }
    end
  end

  def start_search!
    unless can_search?
      select_state_message = 'Ми не закінчили підготовчу роботу:'
      respond_with :message, text: select_state_message, reply_markup: {
        inline_keyboard: current_keyboard,
        resize_keyboard: true,
        one_time_keyboard: true,
        selective: true
      }
      return
    end
    start_message_text = " *Я почав пошук*!\n" \
                         'Будь ласка зачекайте.  Це може зайняти деякий час!'
    respond_with :message, text: start_message_text, parse_mode: 'Markdown'
    results = start_search_process

    stats = if results.present?
              "За Вашим запитом знайдено #{results.count} документів."
            else
              'За Вашим запитом нічго не знайдено. Спробуйте ще з іншими параметрами пошуку:'
            end

    respond_with :message, text: '*Пошук завершено!*', parse_mode: 'Markdown'
    if results.blank?
      respond_with :message, text: stats, parse_mode: 'Markdown', reply_markup: {
        inline_keyboard: [[{ text: 'Почати спочатку', callback_data: 'restart' }]],
        resize_keyboard: true,
        one_time_keyboard: true,
        selective: true
      }
      return
    end
    session[:results] = results
    session[:current_law] = 0
    law = results.first
    keyboard = [{ text: 'Переглянути', url: law[:url] }]
    keyboard += [{ text: 'Наступний', callback_data: 'view_session_result' }] if results.count > 1

    respond_with :message, text: stats

    respond_with :message, text: "```#{law[:text]}```", parse_mode: 'Markdown', reply_markup: {
      inline_keyboard: [keyboard,
                        [{ text: 'Почати спочатку', callback_data: 'restart' }]],
      resize_keyboard: true,
      one_time_keyboard: true,
      selective: true
    }
  end

  def view_session_result!(*)
    total_count = session[:results].count
    next_number = session[:current_law] + 1
    if next_number >= total_count
      session[:current_law] = 0
      next_number = 0
    else
      session[:current_law] = next_number
    end
    law = session[:results][next_number]
    keyboard = [{ text: 'Переглянути', url: law[:url] },
                { text: 'Наступний', callback_data: 'view_session_result' }]

    respond_with :message, text: "```#{law[:text]}```", parse_mode: 'Markdown', reply_markup: {
      inline_keyboard: [keyboard,
                        [{ text: 'Почати спочатку', callback_data: 'restart' }]],
      resize_keyboard: true,
      one_time_keyboard: true,
      selective: true
    }
  end

  def message(message)
    respond_with :message, text: t('.content', text: message['text'])
  end

  def current_callback_message
    update['message']['text']
  end

  def user
    @user = begin
      if update['message']
        update['message']['from']
      else
        update['callback_query']['from']
      end
    end
  end

  def init_session
    session[:state] = :start
    session[:keywords] = ''
    session[:owner] = ''
    session[:document_type] = ''
    session[:search_type] = ''
    session[:results] = nil
    session[:current_law] = 0
  end

  def start_search_process
    p '************************************* SEARCH START **********************************'
    org = all_owners.detect{ |k, v| v == session[:owner] }.first.to_s
    key_word_text = session[:keywords].split(' ').map { |key| URI.encode(key) }.join('+')
    textl = search_type_list.detect{ |k, v| v == session[:search_type] }.first.to_s
    typ = all_types.detect{ |k, v| v == session[:document_type] }.first.to_s
    url = "https://zakon.rada.gov.ua/laws/main?find=2&dat=00000000&user=a&text=#{key_word_text}+&textl=#{textl}&bool=and&org=#{org}&typ=#{typ}&datl=0&yer=0000&mon=00&day=00&numl=2&num=&minjustl=2&minjust="

    html = open(url)
    doc = Nokogiri::HTML(html)
    data = doc.search('div.docs div.doc')
    results = data.map do |law|
      { text: law.content, url: law.search('a').first['href'] }
    end
    p results
    results
  end
end
